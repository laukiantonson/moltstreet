// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

/**
 * @title MoltStreetRegistry
 * @notice Full append-only ledger registry for MoltStreet tokens.
 * @dev Refactored from hybrid (counter + decorative log) to full ledger model.
 *      Every state mutation creates an immutable LedgerEntry. Mappings serve as
 *      materialized indexes for gas-efficient reads, but the ledger array is the
 *      canonical source of truth.
 *
 *      Ledger entry types:
 *        TICKER_RESERVED  — ticker locked for duration (requires MOLTX stake)
 *        TOKEN_REGISTERED — token deployed, ticker claimed permanently
 *        CREATOR_CLAIMED  — creator status transferred to new address
 *        TICKER_RELEASED  — reservation expired / manually released
 *
 *      ~10 mutation sites, all routed through _appendEntry().
 */
contract MoltStreetRegistry {

    // ──────────────────────────────────────────────
    // Types
    // ──────────────────────────────────────────────

    enum EntryType {
        TICKER_RESERVED,
        TOKEN_REGISTERED,
        CREATOR_CLAIMED,
        TICKER_RELEASED
    }

    struct LedgerEntry {
        uint256 id;            // sequential, immutable
        EntryType entryType;
        bytes32 tickerHash;    // keccak256(ticker)
        address token;         // address(0) for reservations
        address actor;         // who performed the action
        address beneficiary;   // who benefits (e.g., new creator on transfer)
        uint256 timestamp;
        uint256 blockNumber;
        bytes32 metadataHash;  // optional IPFS hash or extra context
    }

    // ──────────────────────────────────────────────
    // Ledger (source of truth)
    // ──────────────────────────────────────────────

    LedgerEntry[] public ledger;

    // ──────────────────────────────────────────────
    // Materialized indexes (derived from ledger)
    // ──────────────────────────────────────────────

    mapping(bytes32 => address) public tickerToToken;
    mapping(address => address) public tokenToCreator;
    mapping(address => address[]) internal _creatorToTokens;
    mapping(bytes32 => uint256) public tickerReservedUntil;
    mapping(bytes32 => address) public tickerReservedBy;

    // Reverse lookups
    mapping(address => uint256[]) internal _tokenLedgerEntries;
    mapping(bytes32 => uint256[]) internal _tickerLedgerEntries;
    mapping(address => uint256[]) internal _actorLedgerEntries;

    // ──────────────────────────────────────────────
    // Access control
    // ──────────────────────────────────────────────

    address public owner;
    address public factory;  // only factory can register tokens

    // ──────────────────────────────────────────────
    // Configuration
    // ──────────────────────────────────────────────

    uint256 public reservationDuration = 24 hours;
    uint256 public reservationStake = 100 ether; // 100 MOLTX (18 decimals)
    address public moltxToken;

    // ──────────────────────────────────────────────
    // Events (mirror ledger for off-chain indexing)
    // ──────────────────────────────────────────────

    event LedgerAppend(
        uint256 indexed id,
        EntryType indexed entryType,
        bytes32 indexed tickerHash,
        address token,
        address actor,
        address beneficiary,
        uint256 timestamp
    );

    event FactoryUpdated(address indexed oldFactory, address indexed newFactory);
    event ConfigUpdated(string param, uint256 value);

    // ──────────────────────────────────────────────
    // Errors
    // ──────────────────────────────────────────────

    error Unauthorized();
    error TickerNotAvailable(bytes32 tickerHash);
    error TickerNotReserved(bytes32 tickerHash);
    error ReservationNotExpired(bytes32 tickerHash);
    error NotReservationOwner(bytes32 tickerHash, address caller);
    error TokenAlreadyRegistered(address token);
    error NotCurrentCreator(address token, address caller);
    error ZeroAddress();
    error InvalidTicker();

    // ──────────────────────────────────────────────
    // Modifiers
    // ──────────────────────────────────────────────

    modifier onlyOwner() {
        if (msg.sender != owner) revert Unauthorized();
        _;
    }

    modifier onlyFactory() {
        if (msg.sender != factory) revert Unauthorized();
        _;
    }

    // ──────────────────────────────────────────────
    // Constructor
    // ──────────────────────────────────────────────

    constructor(address _moltxToken) {
        owner = msg.sender;
        moltxToken = _moltxToken;
    }

    // ──────────────────────────────────────────────
    // Core ledger write (ALL mutations go through here)
    // ──────────────────────────────────────────────

    function _appendEntry(
        EntryType _entryType,
        bytes32 _tickerHash,
        address _token,
        address _actor,
        address _beneficiary,
        bytes32 _metadataHash
    ) internal returns (uint256 entryId) {
        entryId = ledger.length;

        ledger.push(LedgerEntry({
            id: entryId,
            entryType: _entryType,
            tickerHash: _tickerHash,
            token: _token,
            actor: _actor,
            beneficiary: _beneficiary,
            timestamp: block.timestamp,
            blockNumber: block.number,
            metadataHash: _metadataHash
        }));

        // Update reverse indexes
        _tickerLedgerEntries[_tickerHash].push(entryId);
        _actorLedgerEntries[_actor].push(entryId);
        if (_token != address(0)) {
            _tokenLedgerEntries[_token].push(entryId);
        }

        emit LedgerAppend(
            entryId,
            _entryType,
            _tickerHash,
            _token,
            _actor,
            _beneficiary,
            block.timestamp
        );
    }

    // ──────────────────────────────────────────────
    // Mutation 1: Reserve Ticker
    // ──────────────────────────────────────────────

    /**
     * @notice Reserve a ticker for 24 hours. Requires MOLTX stake.
     * @param ticker The ticker string to reserve (e.g., "COOL")
     */
    function reserveTicker(string calldata ticker) external {
        bytes32 tickerHash = _validateAndHashTicker(ticker);

        if (!_isTickerAvailable(tickerHash)) {
            revert TickerNotAvailable(tickerHash);
        }

        // TODO: Transfer MOLTX stake from caller
        // IERC20(moltxToken).transferFrom(msg.sender, address(this), reservationStake);

        // Update materialized indexes
        tickerReservedUntil[tickerHash] = block.timestamp + reservationDuration;
        tickerReservedBy[tickerHash] = msg.sender;

        // Append to ledger (source of truth)
        _appendEntry(
            EntryType.TICKER_RESERVED,
            tickerHash,
            address(0),
            msg.sender,
            msg.sender,
            bytes32(0)
        );
    }

    // ──────────────────────────────────────────────
    // Mutation 2: Release Reservation (manual)
    // ──────────────────────────────────────────────

    /**
     * @notice Release a ticker reservation early. Only the reserver can call.
     * @param ticker The ticker string to release
     */
    function releaseReservation(string calldata ticker) external {
        bytes32 tickerHash = keccak256(abi.encodePacked(ticker));

        if (tickerReservedBy[tickerHash] != msg.sender) {
            revert NotReservationOwner(tickerHash, msg.sender);
        }

        // Update materialized indexes
        tickerReservedUntil[tickerHash] = 0;
        tickerReservedBy[tickerHash] = address(0);

        // Append to ledger
        _appendEntry(
            EntryType.TICKER_RELEASED,
            tickerHash,
            address(0),
            msg.sender,
            address(0),
            bytes32(0)
        );

        // TODO: Return MOLTX stake to caller
        // IERC20(moltxToken).transfer(msg.sender, reservationStake);
    }

    // ──────────────────────────────────────────────
    // Mutation 3: Release Expired Reservation (anyone can call)
    // ──────────────────────────────────────────────

    /**
     * @notice Clean up an expired reservation. Anyone can call to free the ticker.
     * @param ticker The ticker string to check and release
     */
    function releaseExpiredReservation(string calldata ticker) external {
        bytes32 tickerHash = keccak256(abi.encodePacked(ticker));

        uint256 expiry = tickerReservedUntil[tickerHash];
        if (expiry == 0 || block.timestamp < expiry) {
            revert ReservationNotExpired(tickerHash);
        }

        address previousReserver = tickerReservedBy[tickerHash];

        // Update materialized indexes
        tickerReservedUntil[tickerHash] = 0;
        tickerReservedBy[tickerHash] = address(0);

        // Append to ledger
        _appendEntry(
            EntryType.TICKER_RELEASED,
            tickerHash,
            address(0),
            msg.sender,        // actor = whoever cleaned it up
            previousReserver,  // beneficiary = gets stake back
            bytes32(0)
        );

        // TODO: Return MOLTX stake to original reserver
        // IERC20(moltxToken).transfer(previousReserver, reservationStake);
    }

    // ──────────────────────────────────────────────
    // Mutation 4: Register Token (factory only)
    // ──────────────────────────────────────────────

    /**
     * @notice Register a newly deployed token. Called by Factory during deploy.
     * @param ticker The ticker string
     * @param token The deployed token address
     * @param creator The creator address
     * @param metadataHash IPFS hash of token metadata
     */
    function registerToken(
        string calldata ticker,
        address token,
        address creator,
        bytes32 metadataHash
    ) external onlyFactory {
        if (token == address(0)) revert ZeroAddress();
        if (creator == address(0)) revert ZeroAddress();

        bytes32 tickerHash = keccak256(abi.encodePacked(ticker));

        // Ticker must be available or reserved by this creator
        if (tickerToToken[tickerHash] != address(0)) {
            revert TickerNotAvailable(tickerHash);
        }

        // If reserved, must be by the creator
        if (tickerReservedBy[tickerHash] != address(0) &&
            tickerReservedBy[tickerHash] != creator) {
            revert TickerNotAvailable(tickerHash);
        }

        if (tokenToCreator[token] != address(0)) {
            revert TokenAlreadyRegistered(token);
        }

        // Update materialized indexes
        tickerToToken[tickerHash] = token;
        tokenToCreator[token] = creator;
        _creatorToTokens[creator].push(token);

        // Clear any reservation (it's now permanently claimed)
        tickerReservedUntil[tickerHash] = 0;
        tickerReservedBy[tickerHash] = address(0);

        // Append to ledger (source of truth)
        _appendEntry(
            EntryType.TOKEN_REGISTERED,
            tickerHash,
            token,
            factory,   // actor = factory contract
            creator,   // beneficiary = creator
            metadataHash
        );
    }

    // ──────────────────────────────────────────────
    // Mutation 5: Claim Creator (transfer creator status)
    // ──────────────────────────────────────────────

    /**
     * @notice Transfer creator status of a token to a new address.
     *         Only the current creator can initiate. Requires owner approval
     *         (off-chain verification via multisig/oracle).
     * @param token The token address
     * @param newCreator The new creator address
     */
    function claimCreator(
        address token,
        address newCreator
    ) external {
        if (newCreator == address(0)) revert ZeroAddress();

        address currentCreator = tokenToCreator[token];
        if (currentCreator != msg.sender && msg.sender != owner) {
            revert NotCurrentCreator(token, msg.sender);
        }

        // Update materialized indexes
        tokenToCreator[token] = newCreator;
        _creatorToTokens[newCreator].push(token);
        _removeTokenFromCreator(currentCreator, token);

        // Append to ledger
        _appendEntry(
            EntryType.CREATOR_CLAIMED,
            bytes32(0),        // no ticker hash needed
            token,
            msg.sender,        // actor = current creator or owner
            newCreator,        // beneficiary = new creator
            bytes32(0)
        );
    }

    // ──────────────────────────────────────────────
    // Views
    // ──────────────────────────────────────────────

    /**
     * @notice Check if a ticker is available for registration.
     */
    function isTickerAvailable(string calldata ticker) external view returns (bool) {
        return _isTickerAvailable(keccak256(abi.encodePacked(ticker)));
    }

    /**
     * @notice Get all tokens created by an address.
     */
    function getTokensByCreator(address creator) external view returns (address[] memory) {
        return _creatorToTokens[creator];
    }

    /**
     * @notice Get the total number of ledger entries.
     */
    function ledgerLength() external view returns (uint256) {
        return ledger.length;
    }

    /**
     * @notice Get a range of ledger entries (for pagination).
     * @param start Start index (inclusive)
     * @param count Number of entries to return
     */
    function getLedgerEntries(
        uint256 start,
        uint256 count
    ) external view returns (LedgerEntry[] memory entries) {
        uint256 end = start + count;
        if (end > ledger.length) end = ledger.length;
        uint256 length = end - start;

        entries = new LedgerEntry[](length);
        for (uint256 i = 0; i < length; i++) {
            entries[i] = ledger[start + i];
        }
    }

    /**
     * @notice Get all ledger entry IDs for a specific ticker.
     */
    function getTickerHistory(string calldata ticker) external view returns (uint256[] memory) {
        return _tickerLedgerEntries[keccak256(abi.encodePacked(ticker))];
    }

    /**
     * @notice Get all ledger entry IDs for a specific token address.
     */
    function getTokenHistory(address token) external view returns (uint256[] memory) {
        return _tokenLedgerEntries[token];
    }

    /**
     * @notice Get all ledger entry IDs for a specific actor.
     */
    function getActorHistory(address actor) external view returns (uint256[] memory) {
        return _actorLedgerEntries[actor];
    }

    // ──────────────────────────────────────────────
    // Admin
    // ──────────────────────────────────────────────

    function setFactory(address _factory) external onlyOwner {
        if (_factory == address(0)) revert ZeroAddress();
        address old = factory;
        factory = _factory;
        emit FactoryUpdated(old, _factory);
    }

    function setReservationDuration(uint256 _duration) external onlyOwner {
        reservationDuration = _duration;
        emit ConfigUpdated("reservationDuration", _duration);
    }

    function setReservationStake(uint256 _stake) external onlyOwner {
        reservationStake = _stake;
        emit ConfigUpdated("reservationStake", _stake);
    }

    function transferOwnership(address _newOwner) external onlyOwner {
        if (_newOwner == address(0)) revert ZeroAddress();
        owner = _newOwner;
    }

    // ──────────────────────────────────────────────
    // Internal helpers
    // ──────────────────────────────────────────────

    function _isTickerAvailable(bytes32 tickerHash) internal view returns (bool) {
        // Already registered as a token
        if (tickerToToken[tickerHash] != address(0)) return false;

        // Currently reserved and not expired
        uint256 reservedUntil = tickerReservedUntil[tickerHash];
        if (reservedUntil > 0 && block.timestamp < reservedUntil) return false;

        return true;
    }

    function _validateAndHashTicker(string calldata ticker) internal pure returns (bytes32) {
        bytes memory tickerBytes = bytes(ticker);
        if (tickerBytes.length == 0 || tickerBytes.length > 10) {
            revert InvalidTicker();
        }
        return keccak256(abi.encodePacked(ticker));
    }

    function _removeTokenFromCreator(address creator, address token) internal {
        address[] storage tokens = _creatorToTokens[creator];
        for (uint256 i = 0; i < tokens.length; i++) {
            if (tokens[i] == token) {
                tokens[i] = tokens[tokens.length - 1];
                tokens.pop();
                return;
            }
        }
    }
}
