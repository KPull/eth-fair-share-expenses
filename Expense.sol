a solidity ^0.4.11;

library Expenses {
    
    struct Expense {
        bytes32 id;
        address payer;
        string description;
        int256 amount;
        uint numBeneficiaries;
        mapping(address => bool) beneficiaries;
    }
    
    struct Key { 
        bytes32 key; 
        bool deleted;
    }
    
    struct IndexedValue { 
        uint keyIndex; 
        Expense value;
    }
    
    struct Map {
        mapping(bytes32 => IndexedValue) data;
        Key[] keys;
        uint size;
    }
    
    function insert(Map storage self, Expense value) internal returns (bool replaced) {
        var key = value.id;
        uint keyIndex = self.data[key].keyIndex;
        self.data[key].value = value;
        if (keyIndex > 0) {
          return true;
        } else {
          keyIndex = self.keys.length;
          self.keys.length++;
          self.data[key].keyIndex = keyIndex + 1;
          self.keys[keyIndex].key = key;
          self.size++;
          return false;
        }
    }
    
    function remove(Map storage self, bytes32 key) internal returns (bool success) {
        uint keyIndex = self.data[key].keyIndex;
        if (keyIndex == 0) {
            return false;
        }
        delete self.data[key];
        self.keys[keyIndex - 1].deleted = true;
        self.size--;
    }
    
    function get(Map storage self, bytes32 key) internal returns (Expense storage expense) {
        expense = self.data[key].value;
        if (expense.id == 0) {
            throw;
        }
    }
    
    function contains(Map storage self, bytes32 key) internal constant returns (bool) {
        return self.data[key].keyIndex > 0;
    }
    
    function iterate_start(Map storage self) internal constant returns (uint keyIndex) {
        return iterate_next(self, uint(-1));
    }
    
    function iterate_next(Map storage self, uint keyIndex) internal constant returns (uint r_keyIndex) {
        keyIndex++;
        while (keyIndex < self.keys.length && self.keys[keyIndex].deleted)
            keyIndex++;
        return keyIndex;
    }
    
    function iterate_valid(Map storage self, uint keyIndex) internal constant returns (bool) {
        return keyIndex < self.keys.length;
    }
    
    function iterate_get(Map storage self, uint keyIndex) internal constant returns (bytes32 key, Expense storage value) {
        key = self.keys[keyIndex].key;
        value = self.data[key].value;
    }
    
}
