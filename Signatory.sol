pragma solidity ^0.4.11;

library Signatories {
    
    struct Signatory {
        address account;
        string description;
        bool signed;
        int256 balance;
    }
    
    struct Key { 
        address key; 
        bool deleted;
    }
    
    struct IndexedValue { 
        uint keyIndex; 
        Signatory value;
    }
    
    struct Map {
        mapping(address => IndexedValue) data;
        Key[] keys;
        uint size;
    }
    
    function insert(Map storage self, Signatory value) internal returns (bool replaced) {
        var key = value.account;
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
    
    function remove(Map storage self, address key) internal returns (bool success) {
        uint keyIndex = self.data[key].keyIndex;
        if (keyIndex == 0) {
            return false;
        }
        delete self.data[key];
        self.keys[keyIndex - 1].deleted = true;
        self.size--;
    }
    
    function get(Map storage self, address key) internal returns (Signatory storage signatory) {
        signatory = self.data[key].value;
        if (signatory.account == 0) {
            throw;
        }
    }
    
    function contains(Map storage self, address key) internal constant returns (bool) {
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
    
    function iterate_get(Map storage self, uint keyIndex) internal constant returns (address key, Signatory storage value) {
        key = self.keys[keyIndex].key;
        value = self.data[key].value;
    }
    
}
