pragma solidity ^0.4.11;

import "Expense.sol";
import "Signatory.sol";

contract FairShareExpenses {
    
    event SignatoryAdded(address account, string description);
    event SignatoryRemoved(address account);
    event ExpenseAdded(bytes32 id, address payer, string description, int256 amount);
    event ExpenseRemoved(bytes32 id);
    event BeneficiaryAdded(bytes32 id, address beneficiary);
    event BeneficiaryRemoved(bytes32 id, address beneficiary);
    event ContractSigned(address account);
    event ContractUnsigned(address account);
    event SignaturesCancelled();
    event ContractLocked();
    event FundsDeposited(address source, uint256 amount);
    event FundsWithdrawn(address payee, uint256 amount);
    
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
    
    modifier cancelsSignatures() {
        _;
        clearSignatures();
    }
    
    function FairShareExpenses() {
        signatories.insert(Signatories.Signatory(msg.sender, false, 0));
        SignatoryAdded(msg.sender, "test");
    }

    
    function addParticipant(address account) whileUnlocked onlySignatories cancelsSignatures {
        if (signatories.insert(Signatories.Signatory(account, false, 0))) {
            throw;
        }
        SignatoryAdded(account, "more test");
    }
    
    function removeSelf() whileUnlocked onlySignatories cancelsSignatures {
        if (!signatories.remove(msg.sender)) {
            throw;
        }
        cancelAllExpenses();
        removeBeneficiaryFromAllExpenses();
        SignatoryRemoved(msg.sender);
    }
    
    function addExpense(string description, int256 amount) whileUnlocked onlySignatories cancelsSignatures returns (bytes32) {
        if (amount <= 0) {
            throw;
        }
        var id = sha3(now, description);
        expenses.insert(Expenses.Expense(id, msg.sender, description, amount, 0));
        expenses.get(id).beneficiaries[msg.sender] = true;
        expenses.get(id).numBeneficiaries++;
        ExpenseAdded(id, msg.sender, description, amount);
        BeneficiaryAdded(id, msg.sender);
        return id;
    }
    
    function cancelAllExpenses() internal {
        for (var i = expenses.iterate_start(); expenses.iterate_valid(i); i = expenses.iterate_next(i)) {
            var (id, expense) = expenses.iterate_get(i);
            if (expense.payer == msg.sender) {
                cancelExpense(id);
            }
        }
    }
    
    function cancelExpense(bytes32 expenseId) whileUnlocked cancelsSignatures {
        Expenses.Expense storage expense = expenses.get(expenseId);
        if (expense.payer != msg.sender) {
            throw;
        }
        expenses.remove(expenseId);
        ExpenseRemoved(expenseId);
    }
    
    function addExpenseBeneficiary(bytes32 expenseId) whileUnlocked cancelsSignatures {
        Expenses.Expense storage expense = expenses.get(expenseId);
        if (!expense.beneficiaries[msg.sender]) {
            expense.beneficiaries[msg.sender] = true;
            expense.numBeneficiaries++;
            BeneficiaryAdded(expenseId, msg.sender);
        }
    }
    
    function removeExpenseBeneficiary(bytes32 expenseId) whileUnlocked cancelsSignatures {
        Expenses.Expense storage expense = expenses.get(expenseId);
        if (expense.beneficiaries[msg.sender]) {
            expense.beneficiaries[msg.sender] = false;
            expense.numBeneficiaries--;
            BeneficiaryRemoved(expenseId, msg.sender);
        }
    }
    
    function removeBeneficiaryFromAllExpenses() internal {
        for (var i = expenses.iterate_start(); expenses.iterate_valid(i); i = expenses.iterate_next(i)) {
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
        ContractSigned(msg.sender);
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
        ContractUnsigned(msg.sender);
    }
    
    function clearSignatures() internal {
        for (var i = signatories.iterate_start(); signatories.iterate_valid(i); i = signatories.iterate_next(i)) {
            var (id, signatory) = signatories.iterate_get(i);
            signatory.signed = false;
        }
        SignaturesCancelled();
    }
    
    function lock() internal {
        locked = true;
        ContractLocked();
    }
    
    function computeBalances() internal {
        for (var i = expenses.iterate_start(); expenses.iterate_valid(i); i = expenses.iterate_next(i)) {
            var (id, expense) = expenses.iterate_get(i);
            var payer = signatories.get(expense.payer);
            // This might have a fractional part which gets lost
            int256 expenseShare = expense.amount / int256(expense.numBeneficiaries);
            // The total is shares multiplied together. This ensures that if any fractional
            // part was lost, the total still equals to the sum of shares
            int256 roundedExpenseTotal = expenseShare * int256(expense.numBeneficiaries);
            
            // Add the total to the payer's withdrawable balance
            payer.balance += roundedExpenseTotal;
            // Deduct the expense share from all beneficiaries' withdrawable balance
            for (var j = signatories.iterate_start(); signatories.iterate_valid(j); j = signatories.iterate_next(j)) {
                var (account, signatory) = signatories.iterate_get(j);
                signatory.balance -= expenseShare;
            }
        }
        computeTotals();
    }
    
    function computeTotals() internal {
        // Compute the total amount that needs to be deposited
        for (var k = signatories.iterate_start(); signatories.iterate_valid(k); k = signatories.iterate_next(k)) {
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
        FundsDeposited(msg.sender, msg.value);
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
        FundsWithdrawn(msg.sender, msg.value);
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
    
    function isSignatory(address account) constant returns (bool) {
        return signatories.contains(account);
    }
    
}
