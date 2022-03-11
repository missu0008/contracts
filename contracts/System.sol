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
  address public constant GENESIS_NODE1 = 0xEe7F0D15bAce58877fBcCe21442d7f8C271a162E;
  address public constant GENESIS_NODE2 = 0x969fb73d144672a22680A844854dF0e1999eA573;
  address public constant GENESIS_NODE3 = 0x9fF4E2D26b4675d91e07BfB04E16DB35a4337b4e;
  address public constant GENESIS_NODE4 = 0xc65380E428F994f436A8838C6aF06Fd2ba01E2a4;
  
  address public constant GENESIS_ADMIN = 0x48BF584350605970000AA9ab1eff4F4721aD040f;
  //创世节点初始化收益地址
  address public constant GENESIS_WITHDARW1 = 0x031f03825b9Cf774B6535538b9fB6443d3BB1eBe;
  address public constant GENESIS_WITHDARW2 = 0x8260eaD62d6e6f0d03c6DDc3a800383c8dfA2923;
  address public constant GENESIS_WITHDARW3 = 0xBe419bDf2CeE79FcadB3126683D1bAa325732b11;
  address public constant GENESIS_WITHDARW4 = 0x37d186ff194F7B9dfb1d7250322d8607a581E0DD;
  
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
