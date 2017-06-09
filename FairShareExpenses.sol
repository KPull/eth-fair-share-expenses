pragma solidity ^0.4.11;

import "Expense.sol";
import "Signatory.sol";

contract FairShareExpenses {
    using Expenses for Expenses.Map;
    using Signatories for Signatories.Map;
    
    uint signatures;
    Signatories.Map public signatories;
    Expenses.Map public expenses;
    
    uint256 public balance;
    int256 public totalAmountToDeposit;
    
    /** 
     * true when all participants have agreed to the expenses listed in the contract
     * and that the contract has now moved to the settlement stage.
     */
    bool public locked;
    
    modifier onlySignatories() {
        if (!signatories.contains(msg.sender)) {
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
    
    modifier whileDepositPhase() {
        if (!locked || totalAmountToDeposit == 0) {
            throw;
        }
        _;
    }
    
    modifier whileWithdrawPhase() {
        if (!locked || totalAmountToDeposit > 0) {
            throw;
        }
        _;
    }
    
    function FairShareExpenses(string creatorDescription) {
        signatories.insert(Signatories.Signatory(msg.sender, creatorDescription, false, 0));
    }

    
    function addParticipant(address account, string description) whileUnlocked onlySignatories {
        if (signatories.insert(Signatories.Signatory(account, description, false, 0))) {
            throw;
        }
    }
    
    function removeSelf() whileUnlocked onlySignatories {
        if (!signatories.remove(msg.sender)) {
            throw;
        }
        cancelAllExpenses();
        removeBeneficiaryFromAllExpenses();
    }
    
    function addExpense(string description, int256 amount) whileUnlocked onlySignatories returns (bytes32) {
        if (amount < 0) {
            throw;
        }
        var id = sha3(now, description);
        expenses.insert(Expenses.Expense(id, msg.sender, description, amount, 0));
        expenses.get(id).beneficiaries[msg.sender] = true;
        expenses.get(id).numBeneficiaries++;
        return id;
    }
    
    function cancelAllExpenses() internal {
        for (var i = expenses.iterate_start(); expenses.iterate_valid(i); expenses.iterate_next(i)) {
            var (id, expense) = expenses.iterate_get(i);
            if (expense.payer == msg.sender) {
                cancelExpense(id);
            }
        }
    }
    
    function cancelExpense(bytes32 expenseId) whileUnlocked {
        Expenses.Expense storage expense = expenses.get(expenseId);
        if (expense.payer != msg.sender) {
            throw;
        }
        expenses.remove(expenseId);
    }
    
    function addExpenseBeneficiary(bytes32 expenseId) whileUnlocked {
        Expenses.Expense storage expense = expenses.get(expenseId);
        if (!expense.beneficiaries[msg.sender]) {
            expense.beneficiaries[msg.sender] = true;
            expense.numBeneficiaries++;
        }
    }
    
    function removeExpenseBeneficiary(bytes32 expenseId) whileUnlocked {
        Expenses.Expense storage expense = expenses.get(expenseId);
        if (expense.beneficiaries[msg.sender]) {
            expense.beneficiaries[msg.sender] = false;
            expense.numBeneficiaries--;
        }
    }
    
    function removeBeneficiaryFromAllExpenses() internal {
        for (var i = expenses.iterate_start(); expenses.iterate_valid(i); expenses.iterate_next(i)) {
            var (id, expense) = expenses.iterate_get(i);
            removeExpenseBeneficiary(id);
        }
    }
    
    function sign() whileUnlocked onlySignatories {
        Signatories.Signatory storage signatory = signatories.get(msg.sender);
        if (signatory.signed) {
            throw;
        }
        signatory.signed = true;
        signatures++;
        if (signatures == signatories.size) {
            lock();
            computeBalances();
        }
    }
    
    function unsign() whileUnlocked onlySignatories {
        Signatories.Signatory storage signatory = signatories.get(msg.sender);
        if (!signatory.signed) {
            throw;
        }
        signatory.signed = false;
        signatures--;
    }
    
    function clearSignatures() internal {
        for (var i = signatories.iterate_start(); signatories.iterate_valid(i); signatories.iterate_next(i)) {
            var (id, signatory) = signatories.iterate_get(i);
            signatory.signed = false;
        }
    }
    
    function lock() internal {
        locked = true;
    }
    
    function computeBalances() internal {
        for (var i = expenses.iterate_start(); expenses.iterate_valid(i); expenses.iterate_next(i)) {
            var (id, expense) = expenses.iterate_get(i);
            var payer = signatories.get(expense.payer);
            // This might have a fractional part which gets lost
            int256 expenseShare = expense.amount / int256(expense.numBeneficiaries);
            // The total is shares multiplied to together. This ensures that if any fractional
            // part was lost, the total still equals to the sum of shares
            int256 roundedExpenseTotal = expenseShare * int256(expense.numBeneficiaries);
            
            // Add the total to the payer's withdrawable balance
            payer.balance += roundedExpenseTotal;
            // Deduct the expense share from all beneficiaries' withdrawable balance
            for (var j = signatories.iterate_start(); signatories.iterate_valid(j); signatories.iterate_next(j)) {
                var (account, signatory) = signatories.iterate_get(j);
                signatory.balance -= expenseShare;
            }
        }
        computeTotals();
    }
    
    function computeTotals() internal {
        // Compute the total amount that needs to be deposited
        for (var k = signatories.iterate_start(); signatories.iterate_valid(k); signatories.iterate_next(k)) {
            var (account, signatory) = signatories.iterate_get(k);
            if (signatory.balance > 0) {
                totalAmountToDeposit += signatory.balance;                
            }
        }
    }
    
    function deposit() onlySignatories whileDepositPhase payable {
        var signatory = signatories.get(msg.sender);
        var owed = -signatory.balance;
        if (int256(msg.value) > owed) {
            throw;
        }
        signatory.balance += int256(msg.value);
        totalAmountToDeposit -= int256(msg.value);
        balance += msg.value;
    }
    
    function withdraw() onlySignatories whileWithdrawPhase {
        var signatory = signatories.get(msg.sender);
        var owed = signatory.balance;
        if (owed <= 0) {
            throw;
        }
        var amountToSend = uint256(owed);
        signatory.balance = 0;
        balance -= amountToSend;
        if (!msg.sender.send(amountToSend)) {
            throw;
        }
    }
    
    function getMyBalance() constant onlySignatories returns (int256) {
        if (!locked) {
            throw;
        }
        return signatories.get(msg.sender).balance;
    }
    
}
