// SPDX-License-Identifier: MIT
pragma solidity ^0.8.17;

// Uncomment this line to use console.log
// import "hardhat/console.sol";
import "./data-segment/Proof.sol";

contract Aggregator is Proof {
    enum Status {
        Pending,
        Completed
    }

    uint256 public transactionId;
    uint256 public aggregatorFeePerBytes;
    mapping(address => uint256) public balances;
    mapping(uint256 => Status) public transactionIdStatus;

    error FeeNotEnough();
    error BalanceNotEnough();
    error TransferFailed();
    error IncorrectTransactionId();

    event SubmitAggregatorRequest(uint256 indexed _transactionId, bytes _cid, address _sender);
    event CompleteAggregatorRequest(
        uint256 indexed _transactionId,
        uint64 _dealId,
        bytes _cid,
        InclusionAuxData _inclusionAuxData
    );

    /// @dev Constructor that sets the fee per byte for the aggregator.
    /// @param _aggregatorFeePerBytes The fee per byte.
    constructor(uint256 _aggregatorFeePerBytes) {
        transactionId = 0;
        aggregatorFeePerBytes = _aggregatorFeePerBytes;
    }

    /// @dev User Submits a new aggregator request.
    /// @param _cid The content identifier of the file.
    /// @return The transaction ID of the new request.
    function submit(bytes memory _cid) external payable returns (uint256) {
        // Check if the fee is enough
        if (msg.value == 0) {
            revert FeeNotEnough();
        }
        // Transfer the Ether
        (bool success, ) = address(this).call{value: msg.value}("");
        if (!success) {
            revert TransferFailed();
        }

        // Update the mappings
        balances[msg.sender] += msg.value;

        // Increment the transaction ID and update its status
        transactionId++;
        transactionIdStatus[transactionId] = Status.Pending;

        // Emit the event
        emit SubmitAggregatorRequest(transactionId, _cid, msg.sender);

        return transactionId;
    }

    /// @dev Completes an aggregator request by verifying the inclusion proof and transferring the fee to aggregator.
    /// @dev To be called by the aggregator.
    /// @param _id The transaction ID of the request.
    /// @param _dealId The deal ID.
    /// @param _cid The content identifier of the file.
    /// @param _proof The inclusion proof.
    /// @param _verifierData The verifier data.
    /// @return The auxiliary data of the inclusion.
    function complete(
        uint256 _id,
        uint64 _dealId,
        bytes memory _cid,
        InclusionProof memory _proof,
        InclusionVerifierData memory _verifierData
    ) external returns (InclusionAuxData memory) {
        // Check if the transaction ID is correct
        if (transactionIdStatus[_id] != Status.Pending) {
            revert IncorrectTransactionId();
        }

        // verify the CID inclusion proof
        InclusionAuxData memory inclusionAuxData = computeExpectedAuxDataWithDeal(
            _dealId,
            _proof,
            _verifierData
        );
        uint256 fee = _verifierData.sizePc * aggregatorFeePerBytes;
        // Update the mappings
        balances[msg.sender] -= fee;

        // Transfer the Ether
        (bool success, ) = msg.sender.call{value: fee}("");
        if (!success) {
            revert TransferFailed();
        }

        // Emit the event
        emit CompleteAggregatorRequest(_id, _dealId, _cid, inclusionAuxData);
    }

    /// @dev Withdraws Ether from the contract.
    /// @param amount The amount of Ether to withdraw.
    function withdraw(uint256 amount) external {
        // Check if the amount is enough
        if (amount > balances[msg.sender]) {
            revert BalanceNotEnough();
        }

        // Update the mappings
        balances[msg.sender] -= amount;

        // Transfer the Ether
        (bool success, ) = msg.sender.call{value: amount}("");
        if (!success) {
            revert TransferFailed();
        }
    }

    /// @dev Receives Ether and updates the balance.
    receive() external payable {
        // Update the balance
        balances[msg.sender] += msg.value;
    }
}
