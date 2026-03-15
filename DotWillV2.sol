// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

/**
 * @title  DotWill
 * @notice On-chain inheritance with a heartbeat dead man's switch.
 *         Built for the Polkadot Solidity Hackathon 2026.
 *
 * @dev    Deployed on Polkadot Hub (Westend testnet via PolkaVM).
 *
 * ── How it works ──────────────────────────────────────────────────────────
 *  1. Owner deploys with a list of beneficiaries + their shares (must = 100%)
 *  2. Owner calls heartbeat() regularly to prove they are alive
 *  3. If owner misses the interval + grace period, ANYONE can call trigger()
 *  4. trigger() unlocks the will — beneficiaries can now call claim()
 *  5. Owner can deposit/withdraw native tokens (DOT/WND) at any time
 *  6. Owner can update beneficiaries and interval while will is NOT triggered
 *  7. Owner can permanently revoke the will and withdraw all funds
 * ──────────────────────────────────────────────────────────────────────────
 */
contract DotWillV2 {

    // ─── Constants ────────────────────────────────────────────────────────
    uint256 public constant MIN_INTERVAL   = 1 days;
    uint256 public constant MAX_INTERVAL   = 365 days;
    uint256 public constant MIN_GRACE      = 1 days;
    uint256 public constant MAX_GRACE      = 30 days;
    uint256 public constant MAX_BENES      = 10;
    uint256 public constant SHARE_PRECISION = 10_000; // 100.00% = 10000 bps

    // ─── Structs ──────────────────────────────────────────────────────────
    struct Beneficiary {
        address payable wallet;
        uint256 shareBps;   // e.g. 6000 = 60.00%
        string  label;      // human-readable name, stored off-chain friendly
        bool    claimed;
    }

    // ─── State ────────────────────────────────────────────────────────────
    address public owner;

    uint256 public heartbeatInterval;  // seconds between required check-ins
    uint256 public gracePeriod;        // extra seconds after missed heartbeat
    uint256 public lastHeartbeat;      // timestamp of last heartbeat

    bool public triggered;  // true = owner missed deadline, claims unlocked
    bool public revoked;    // true = owner shut down the will

    Beneficiary[] public beneficiaries;

    // track total shares to enforce = 10000
    uint256 private _totalShares;

    // ─── Events ───────────────────────────────────────────────────────────
    event Deposited(address indexed from, uint256 amount);
    event Heartbeat(address indexed owner, uint256 timestamp, uint256 nextDeadline);
    event WillTriggered(address indexed triggeredBy, uint256 timestamp);
    event Claimed(address indexed beneficiary, uint256 amount, uint256 shareBps);
    event BeneficiariesUpdated(uint256 count);
    event IntervalUpdated(uint256 newInterval, uint256 newGrace);
    event Revoked(address indexed owner, uint256 refundAmount);
    event MessageUpdated(bytes32 indexed messageHash);

    // ─── Errors ───────────────────────────────────────────────────────────
    error NotOwner();
    error AlreadyTriggered();
    error AlreadyRevoked();
    error NotTriggered();
    error DeadlineNotPassed();
    error AlreadyClaimed();
    error InvalidShares();
    error TooManyBeneficiaries();
    error ZeroAddress();
    error IntervalOutOfRange();
    error GraceOutOfRange();
    error NothingToWithdraw();
    error TransferFailed();

    // ─── Modifiers ────────────────────────────────────────────────────────
    modifier onlyOwner() {
        if (msg.sender != owner) revert NotOwner();
        _;
    }

    modifier notTriggered() {
        if (triggered) revert AlreadyTriggered();
        _;
    }

    modifier notRevoked() {
        if (revoked) revert AlreadyRevoked();
        _;
    }

    modifier isTriggered() {
        if (!triggered) revert NotTriggered();
        _;
    }

    // ─── Constructor ──────────────────────────────────────────────────────

    /**
     * @param _realOwner           The actual owner (user's wallet). Needed when
     *                             deployed via factory (msg.sender would be factory).
     *                             Pass address(0) to default to msg.sender.
     * @param _beneficiaryWallets  Array of beneficiary addresses
     * @param _shareBps            Array of shares in basis points (must sum to 10000)
     * @param _labels              Array of human-readable labels (e.g. "Sarah")
     * @param _heartbeatInterval   Seconds between required heartbeats (e.g. 604800 = 7 days)
     * @param _gracePeriod         Extra seconds after missed interval before will triggers
     */
    constructor(
        address        _realOwner,
        address payable[] memory _beneficiaryWallets,
        uint256[]          memory _shareBps,
        string[]           memory _labels,
        uint256 _heartbeatInterval,
        uint256 _gracePeriod
    ) payable {
        if (_heartbeatInterval < MIN_INTERVAL || _heartbeatInterval > MAX_INTERVAL)
            revert IntervalOutOfRange();
        if (_gracePeriod < MIN_GRACE || _gracePeriod > MAX_GRACE)
            revert GraceOutOfRange();

        // If _realOwner is provided use it (factory case), else use msg.sender (direct deploy)
        owner             = _realOwner != address(0) ? _realOwner : msg.sender;
        heartbeatInterval = _heartbeatInterval;
        gracePeriod       = _gracePeriod;
        lastHeartbeat     = block.timestamp;

        _setBeneficiaries(_beneficiaryWallets, _shareBps, _labels);
    }

    // ─── Core: Heartbeat ──────────────────────────────────────────────────

    /**
     * @notice Owner calls this regularly to prove they are alive.
     *         Resets the countdown timer.
     */
    function heartbeat() external onlyOwner notTriggered notRevoked {
        lastHeartbeat = block.timestamp;
        emit Heartbeat(msg.sender, block.timestamp, deadline());
    }

    // ─── Core: Trigger ────────────────────────────────────────────────────

    /**
     * @notice Anyone can call this once the deadline has passed.
     *         Unlocks the will for beneficiaries to claim.
     */
    function trigger() external notTriggered notRevoked {
        if (block.timestamp <= deadline()) revert DeadlineNotPassed();
        triggered = true;
        emit WillTriggered(msg.sender, block.timestamp);
    }

    // ─── Core: Claim ──────────────────────────────────────────────────────

    /**
     * @notice Beneficiary calls this after the will is triggered.
     *         Pays out their share of the contract balance.
     * @param index  Position of caller in beneficiaries array
     */
    function claim(uint256 index) external isTriggered notRevoked {
        Beneficiary storage bene = beneficiaries[index];

        if (bene.wallet != msg.sender)  revert NotOwner();
        if (bene.claimed)               revert AlreadyClaimed();

        uint256 balance = address(this).balance;
        if (balance == 0)               revert NothingToWithdraw();

        // Calculate this beneficiary's share of current balance
        uint256 payout = (balance * bene.shareBps) / SHARE_PRECISION;
        bene.claimed   = true;

        (bool ok,) = bene.wallet.call{value: payout}("");
        if (!ok) revert TransferFailed();

        emit Claimed(bene.wallet, payout, bene.shareBps);
    }

    // ─── Owner: Deposit ───────────────────────────────────────────────────

    /**
     * @notice Owner deposits native tokens into the will vault.
     */
    function deposit() external payable onlyOwner notRevoked {
        emit Deposited(msg.sender, msg.value);
    }

    receive() external payable {
        emit Deposited(msg.sender, msg.value);
    }

    // ─── Owner: Withdraw ──────────────────────────────────────────────────

    /**
     * @notice Owner can withdraw any amount while will is NOT triggered.
     * @param amount  Amount in wei to withdraw (0 = withdraw all)
     */
    function withdraw(uint256 amount) external onlyOwner notTriggered notRevoked {
        uint256 bal = address(this).balance;
        if (bal == 0) revert NothingToWithdraw();

        uint256 toSend = amount == 0 ? bal : amount;
        (bool ok,) = payable(owner).call{value: toSend}("");
        if (!ok) revert TransferFailed();
    }

    // ─── Owner: Update Beneficiaries ──────────────────────────────────────

    /**
     * @notice Replace all beneficiaries. Can only be done before triggering.
     */
    function updateBeneficiaries(
        address payable[] memory _wallets,
        uint256[]          memory _shareBps,
        string[]           memory _labels
    ) external onlyOwner notTriggered notRevoked {
        // Clear existing
        delete beneficiaries;
        _totalShares = 0;
        _setBeneficiaries(_wallets, _shareBps, _labels);
    }

    // ─── Owner: Update Interval ───────────────────────────────────────────

    /**
     * @notice Update heartbeat interval and grace period.
     */
    function updateInterval(
        uint256 _heartbeatInterval,
        uint256 _gracePeriod
    ) external onlyOwner notTriggered notRevoked {
        if (_heartbeatInterval < MIN_INTERVAL || _heartbeatInterval > MAX_INTERVAL)
            revert IntervalOutOfRange();
        if (_gracePeriod < MIN_GRACE || _gracePeriod > MAX_GRACE)
            revert GraceOutOfRange();

        heartbeatInterval = _heartbeatInterval;
        gracePeriod       = _gracePeriod;

        emit IntervalUpdated(_heartbeatInterval, _gracePeriod);
    }

    // ─── Owner: Store Message Hash ────────────────────────────────────────

    /**
     * @notice Store a hash of the last message on-chain (actual message stored off-chain).
     *         Provides proof of authenticity without storing sensitive content on-chain.
     * @param messageHash  keccak256 hash of the encrypted last message
     */
    function setMessageHash(bytes32 messageHash) external onlyOwner notRevoked {
        emit MessageUpdated(messageHash);
    }

    // ─── Owner: Revoke ────────────────────────────────────────────────────

    /**
     * @notice Permanently revoke the will. Refunds entire balance to owner.
     *         Cannot be undone.
     */
    function revoke() external onlyOwner notTriggered notRevoked {
        revoked = true;
        uint256 bal = address(this).balance;

        if (bal > 0) {
            (bool ok,) = payable(owner).call{value: bal}("");
            if (!ok) revert TransferFailed();
        }

        emit Revoked(owner, bal);
    }

    // ─── View Functions ───────────────────────────────────────────────────

    /**
     * @notice Timestamp after which trigger() can be called.
     */
    function deadline() public view returns (uint256) {
        return lastHeartbeat + heartbeatInterval + gracePeriod;
    }

    /**
     * @notice Seconds remaining until trigger() can be called.
     *         Returns 0 if already past deadline.
     */
    function timeRemaining() public view returns (uint256) {
        uint256 d = deadline();
        if (block.timestamp >= d) return 0;
        return d - block.timestamp;
    }

    /**
     * @notice Returns true if the deadline has passed and trigger() can be called.
     */
    function canTrigger() public view returns (bool) {
        return !triggered && !revoked && block.timestamp > deadline();
    }

    /**
     * @notice Get all beneficiaries as arrays.
     */
    function getBeneficiaries() external view returns (
        address[] memory wallets,
        uint256[] memory shares,
        string[]  memory labels,
        bool[]    memory claimed
    ) {
        uint256 len = beneficiaries.length;
        wallets = new address[](len);
        shares  = new uint256[](len);
        labels  = new string[](len);
        claimed = new bool[](len);

        for (uint256 i; i < len; i++) {
            wallets[i] = beneficiaries[i].wallet;
            shares[i]  = beneficiaries[i].shareBps;
            labels[i]  = beneficiaries[i].label;
            claimed[i] = beneficiaries[i].claimed;
        }
    }

    /**
     * @notice Full status snapshot — useful for frontend.
     */
    function status() external view returns (
        uint256 balance,
        uint256 lastBeat,
        uint256 nextDeadline,
        uint256 secondsLeft,
        bool    willTriggered,
        bool    willRevoked,
        uint256 numBeneficiaries
    ) {
        return (
            address(this).balance,
            lastHeartbeat,
            deadline(),
            timeRemaining(),
            triggered,
            revoked,
            beneficiaries.length
        );
    }

    // ─── Internal ─────────────────────────────────────────────────────────

    function _setBeneficiaries(
        address payable[] memory _wallets,
        uint256[]          memory _shareBps,
        string[]           memory _labels
    ) internal {
        uint256 len = _wallets.length;

        if (len == 0 || len > MAX_BENES)         revert TooManyBeneficiaries();
        if (_shareBps.length != len)              revert InvalidShares();
        if (_labels.length   != len)              revert InvalidShares();

        uint256 total;
        for (uint256 i; i < len; i++) {
            if (_wallets[i] == address(0))        revert ZeroAddress();
            total += _shareBps[i];
            beneficiaries.push(Beneficiary({
                wallet:   _wallets[i],
                shareBps: _shareBps[i],
                label:    _labels[i],
                claimed:  false
            }));
        }

        if (total != SHARE_PRECISION)             revert InvalidShares();
        _totalShares = total;

        emit BeneficiariesUpdated(len);
    }
}
