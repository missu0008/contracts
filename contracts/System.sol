pragma solidity 0.6.4;

contract System {

  bool public alreadyInit;

  uint16 constant public bscChainID = 0x0060;

  address public constant VALIDATOR_CONTRACT_ADDR = 0x0000000000000000000000000000000000001000;

  address public constant NOMINATION_VOTE_ADDR = 0x0000000000000000000000000000000000003000;

  address public constant SLASH_CONTRACT_ADDR = 0x0000000000000000000000000000000000001001;

  //INIT_VALIDATORSET_BYTES加在这
  bytes public constant INIT_VALIDATORSET_BYTES = hex"f84580f842f84094f9056de9c0c6e8fC3097c3612110641190e0C37b94f9056de9c0c6e8fC3097c3612110641190e0C37b94f9056de9c0c6e8fC3097c3612110641190e0C37b64";

  //创世节点初始化验证
  address public constant GENESIS_NODE = 0xf9056de9c0c6e8fC3097c3612110641190e0C37b;

  modifier onlyCoinbase() {
    require(msg.sender == block.coinbase, "the message sender must be the block producer");
    _;
  }

  modifier onlyNotInit() {
    require(!alreadyInit, "the contract already init");
    _;
  }

  modifier onlyInit() {
    require(alreadyInit, "the contract not init yet");
    _;
  }

  modifier onlyNominationVoteContract(){
    require(msg.sender == NOMINATION_VOTE_ADDR, "the message sender must be NominationVote contract");
    _;
  }
  
  modifier onlyValidatorContract() {
    require(msg.sender == VALIDATOR_CONTRACT_ADDR, "the message sender must be validatorSet contract");
    _;
  }

  modifier onlySlash() {
    require(msg.sender == SLASH_CONTRACT_ADDR, "the message sender must be slash contract");
    _;
  }

  // Not reliable, do not use when need strong verify
  function isContract(address addr) internal view returns (bool) {
    uint size;
    assembly { size := extcodesize(addr) }
    return size > 0;
  }
}
