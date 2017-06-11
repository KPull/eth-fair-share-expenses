const fs = require('fs');
const solc = require('solc');
const Web3 = require('web3');

const web3 = new Web3(new Web3.providers.HttpProvider("http://localhost:8545"));

const inputs = {
	'FairShareExpenses.sol': fs.readFileSync('FairShareExpenses.sol').toString(),
	'Expense.sol': fs.readFileSync('Expense.sol').toString(),
	'Signatory.sol': fs.readFileSync('Signatory.sol').toString()
};
const output = solc.compile({sources: inputs}, 1);
const bytecode = output.contracts['FairShareExpenses.sol:FairShareExpenses'].bytecode;
const abi = JSON.parse(output.contracts['FairShareExpenses.sol:FairShareExpenses'].interface);

const contract = web3.eth.contract(abi);

console.log('author:', web3.eth.coinbase);
web3.personal.unlockAccount(web3.eth.coinbase, "");
console.log('bytecode:', bytecode);
const contractInstance = contract.new({
    data: '0x' + bytecode,
    from: web3.eth.coinbase,
    gas: 4217728, 
}, (err, res) => {
    if (err) {
        console.log(err);
        return;
    }

    // Log the tx, you can explore status with eth.getTransaction()
    console.log(res.transactionHash);

    // If we have an address property, the contract was deployed
    if (res.address) {
        console.log('Contract address: ' + res.address);
    }
});

console.log('ABI:', JSON.stringify(abi));
