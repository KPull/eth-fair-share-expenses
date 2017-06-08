pragma solidity ^0.4.11;

contract FairShareExpenses {
    
    struct Expense {
        bytes32 id;
        address payer;
        string description;
        uint256 amount;
        uint numBeneficiaries;
        mapping(address => bool) beneficiaries;
    }
    
    address[] public participants;
    mapping(address => bool) public participating;
    mapping(address => bool) public signed;
    
    Expense[] public expenses;
    
    /** 
     * true when all participants have agreed to the expenses listed in the contract
     * and that the contract has now moved to the settlement stage.
     */
    bool public locked;
    
    modifier onlyParticipants() {
        if (!participating[msg.sender]) {
            throw;
        }
        _;
    }
    
    modifier whileUnlocked() {
        if (locked) {
            throw;
        }
        _;
    }
    
    function FairShareExpenses() {
        participants.push(msg.sender);
        participating[msg.sender] = true;
    }
    
    function addParticipant(address account) whileUnlocked onlyParticipants {
        if (participating[account]) {
            throw;
        }
        participants.push(account);
        participating[account] = true;
        signed[account] = false;
    }
    
    function removeSelf() whileUnlocked onlyParticipants {
        participating[msg.sender] = false;
        signed[msg.sender] = false;
        // TODO: Cancel expenses that were added by the msg.sender
        // TODO: Remove as beneficiary from all expenses
        for (uint i = 0; i < participants.length; i++) {
            if (participants[i] == msg.sender) {
                delete participants[i];
                return;
            }
        }
    }
    
    function addExpense(string description, uint256 amount) whileUnlocked onlyParticipants returns (bytes32) {
        var id = sha3(now, description);
        expenses.push(Expense(id, msg.sender, description, amount, 1));
        expenses[expenses.length].beneficiaries[msg.sender] = true;
        return id;
    }
    
    function cancelExpense(bytes32 expenseId) whileUnlocked {
        
    }
    
}
