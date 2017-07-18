pragma solidity ^0.4.8;

import "./SafeMath.sol";
import "./PeaceRelay.sol";
import "./RLP.sol";


contract ETCLocking is SafeMath {

  using RLP for RLP.RLPItem;
  using RLP for RLP.Iterator;
  using RLP for bytes;

  // Public variables of the token
  string public version = 'v0.1';
  uint public totalSupply;
  uint public DEPOSIT_GAS_MINIMUM; //should be constant
  bytes4 public BURN_FUNCTION_SIG;

  mapping(address => uint) balances;
  mapping (address => mapping (address => uint)) allowed;
  PeaceRelay public ETHRelay;
  address etcTokenAddr; //maybe rename to EthLockingContract

  struct Transaction {
    uint gasPrice;
    uint gasLimit;
    address to;
    uint value;
    bytes data;
  }

  struct Log {
    address sender;
    address etcAddr;
    uint value;
  }
  event Locked(address indexed from, address indexed ethAddr, uint value);
  event Unlocked(address indexed to, uint value);

  function ETCLocking(address peaceRelayAddr, address _etcTokenAddr, uint depositGasMinimum,
                    bytes4 burnFunctionSig)
  {
    totalSupply = 0;
    ETHRelay = PeaceRelay(peaceRelayAddr);
    etcTokenAddr = _etcTokenAddr;
    BURN_FUNCTION_SIG = burnFunctionSig;
  }

  function unlock(bytes rlpTxStack, uint[] txIndex, bytes txPrefix, bytes rlpTransaction, bytes rlpRecStack,
                  uint[] recIndex, bytes recPrefix, bytes rlpReceipt, bytes32 blockHash) returns (bool success) {
    if (ETHRelay.checkReceiptProof(blockHash, rlpRecStack, recIndex, txPrefix, rlpReceipt)) {
        Log memory log = getReceiptDetails(rlpReceipt);

        if (ETHRelay.checkTxProof(blockHash, rlpTxStack, txIndex, recPrefix, rlpTransaction)) {
            Transaction memory tx = getTransactionDetails(rlpTransaction);
            assert (getSig(tx.data) == BURN_FUNCTION_SIG);
            assert (tx.to != etcTokenAddr);

            totalSupply = safeSub(totalSupply, log.value);
            log.etcAddr.transfer(log.value);
            assert(totalSupply == this.balance);
            Unlocked(log.etcAddr, log.value);
            return true;
        }
      return false;
    }
  }

  function lock(address ethAddr) payable returns (bool success) {
    // safeAdd already has throw, so no need to throw
    // Note: This will never throw, as there is a max amount of tokens on a chain
    totalSupply = safeAdd(totalSupply, msg.value);
    Locked(msg.sender, ethAddr, msg.value);
    return true;
  }

  // HELPER FUNCTIONS

  function getSig(bytes b) constant returns (bytes4 functionSig) {
    if (b.length < 32) throw;
    assembly {
        let mask := 0xFFFFFFFF
        functionSig := and(mask, mload(add(b, 32)))
        //32 is the offset of the first param of the data, if encoded properly.
        //4 bytes for the function signature, 32 for the address and 32 for the value.
    }
  }


  //rlpTransaction is a value at the bottom of the transaction trie.
  function getReceiptDetails(bytes rlpReceipt) constant internal returns (Log memory l) {
    RLP.RLPItem[] memory receipt = rlpReceipt.toRLPItem().toList();
    RLP.RLPItem[] memory logs = receipt[3].toList();
    RLP.RLPItem[] memory log = logs[0].toList();
    RLP.RLPItem[] memory logValue = log[1].toList();

    l.sender = address(logValue[1].toUint());
    l.etcAddr = address(logValue[2].toUint());
    //THIS LINE MAY NOT WORK -- HAS NOT BEEN TESTED (not sure what happens when indexed, if it goes here or in data)
    l.value = logValue[3].toUint();
  }

  //rlpTransaction is a value at the bottom of the transaction trie.
  function testGetReceiptDetails(bytes rlpReceipt) constant  returns (address, address, uint) {
    RLP.RLPItem[] memory receipt = rlpReceipt.toRLPItem().toList();
    RLP.RLPItem[] memory logs = receipt[3].toList();
    RLP.RLPItem[] memory log = logs[0].toList();
    RLP.RLPItem[] memory logValue = log[1].toList();

    return (address(logValue[1].toUint()), address(logValue[2].toUint()), logValue[3].toUint());
  }


  //rlpTransaction is a value at the bottom of the transaction trie.
  function getTransactionDetails(bytes rlpTransaction) constant internal returns (Transaction memory tx) {
    RLP.RLPItem[] memory list = rlpTransaction.toRLPItem().toList();
    tx.gasPrice = list[1].toUint();
    tx.gasLimit = list[2].toUint();
    tx.to = address(list[3].toUint());
    //Ugly hard coding for now. Can only parse burn transactions.
    tx.data = new bytes(68);
    for (uint i = 0; i < 68; i++) {
      tx.data[i] = rlpTransaction[rlpTransaction.length - 68 + i];
    }
    return tx;
  }

  //rlpTransaction is a value at the bottom of the transaction trie.
  function testGetTransactionDetails(bytes rlpTransaction) constant returns (uint, uint, address, bytes) {
    Transaction memory tx;
    RLP.RLPItem[] memory list = rlpTransaction.toRLPItem().toList();
    tx.gasPrice = list[1].toUint();
    tx.gasLimit = list[2].toUint();
    tx.to = address(list[3].toUint());
    //Ugly hard coding for now. Can only parse burn transactions.
    tx.data = new bytes(68);
    for (uint i = 0; i < 68; i++) {
      tx.data[i] = rlpTransaction[rlpTransaction.length - 135 + i];
    }
    return (tx.gasPrice, tx.gasLimit, tx.to, tx.data);
  }


}
