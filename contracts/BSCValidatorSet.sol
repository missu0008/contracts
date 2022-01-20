pragma solidity 0.6.4;
pragma experimental ABIEncoderV2;

import "./System.sol";
import "./lib/BytesToTypes.sol";
import "./lib/Memory.sol";
import "./lib/SafeMath.sol";
import "./lib/RLPDecode.sol";
import "./lib/CmnPkg.sol";


contract BSCValidatorSet is  System  {

  using SafeMath for uint256;

  using RLPDecode for *;

  uint256 public constant MAX_NUM_OF_VALIDATORS = 41;

  /*********************** state of the contract **************************/
  Validator[] public currentValidatorSet;
  uint256 public expireTimeSecondGap;
  uint256 public totalInComing;

  // key is the `consensusAddress` of `Validator`,
  // value is the index of the element in `currentValidatorSet`.
  mapping(address =>uint256) public currentValidatorSetMap;

  struct Validator{
    address consensusAddress;
    //是否是验证人（false表示为验证人或候选,true表示已取消成为验证人或候选）
    bool jailed;
    uint256 incoming;

    //票数，新增
    uint64 votes;
    //分红比例
    int8 ratio;
    //每票奖励
    uint256 reTicket;
    //累计获得的奖励
    uint256 totalInComing;
    //交易总数
    uint64 totaltransactions;
    //打包的区块数
    uint blocks;
  }

  //当前正在出块的验证人
  //mapping(address => uint256) produceValidatorMap;
  //初始化验证人的数量
  int8 public INITIAL_VALIDATOR;

  /*********************** modifiers **************************/
  modifier noEmptyDeposit() {
    require(msg.value > 0, "deposit value is zero");
    _;
  }

  /*********************** events **************************/
  event deprecatedDeposit(address indexed validator, uint256 amount);
  event validatorDeposit(address indexed validator, uint256 amount);

  /*********************** init **************************/
  function init() external onlyNotInit{
    Validator memory validator;
    validator.consensusAddress = GENESIS_NODE;
    //创世节点默认分红10%
    validator.ratio = 10;
    currentValidatorSet.push(validator);
    currentValidatorSetMap[GENESIS_NODE] = 1;
    //初始化节点数量
    INITIAL_VALIDATOR = 1;
    alreadyInit = true;
  }

  /**********************以下为新增内容，只能投票合约更新 **********************************/

  //更新票数 status为true表示增加，false减少
  function updateVoter(uint64 ballot,address valAddr , bool status) external onlyInit onlyNominationVoteContract{
    uint256 index = currentValidatorSetMap[valAddr];
    require(index > 0,"verifier does not exist");
    Validator storage validator = currentValidatorSet[index-1];
    require( !validator.jailed, "verifier does not exist");
    if(status){
      calculateVoteTicket(validator,ballot);
    }else{
      calculateUnVoteTicket(validator,ballot);
    }
    checkRanking();
  }

  //更新验证人
  function updateCandidates(address user ,int8 ratio)external onlyInit onlyNominationVoteContract{
    //判断是否已是候选人
    uint n = currentValidatorSet.length;
    bool flag = true;
    for (uint i = 0 ; i<n ; i ++){
        if( currentValidatorSet[i].consensusAddress == user && !currentValidatorSet[i].jailed ){
            flag = false;
            break;
        }
    }
    require(flag, "already a candidate");

    //先看缓存表
    uint256 index = currentValidatorSetMap[user];
    if(index <= 0){
      Validator memory validator;
      validator.consensusAddress = user;
      validator.jailed = false;
      //validator.status = true;
      validator.ratio = ratio;
      currentValidatorSet.push(validator);
      currentValidatorSetMap[user] = currentValidatorSet.length;
    }else{
      Validator storage validator = currentValidatorSet[index-1];
      validator.jailed = false;
      validator.ratio = ratio;
    }
  }

  //取消成为验证人
  function cancleCandidates(address user)external onlyInit onlyNominationVoteContract{
    uint256 n = currentValidatorSet.length;
    //判断当前用户是否是验证人
    bool flag = false;
    uint i = 0;
    for ( ; i < n ; i++){
        if( currentValidatorSet[i].consensusAddress == user && !currentValidatorSet[i].jailed){
            currentValidatorSet[i].jailed = true;
           // currentValidatorSet[i].status = false;
            flag = true;
            break;
        }
    }
    require(flag, "not a candidate"); 
  }

  //收益提现
  function withdrawGst(address user , uint256 value)external onlyInit onlyNominationVoteContract{
    address payable payableAddr = payable(user);
    payableAddr.transfer(value);
  }

  //更新验证人领取奖励
  function withdrawValidatorGst(address user,uint256 amount)external onlyInit onlyNominationVoteContract{
    uint256 index = currentValidatorSetMap[user];
    if( index <= 0){
      return;
    }
    Validator storage validator = currentValidatorSet[index-1];
    if(validator.incoming <= 0){
      return;
    }
    if( validator.incoming > amount ){
      validator.incoming  = validator.incoming.sub(amount);
    }else{
      validator.incoming = 0;
    }
  }


  /*********************** 底层出块调用此接口 **************************/
  function deposit(address valAddr) external payable onlyCoinbase onlyInit noEmptyDeposit{
    uint256 value = msg.value;
    uint256 index = currentValidatorSetMap[valAddr];

    if (index>0) {
      Validator storage validator = currentValidatorSet[index-1];
      if (validator.jailed) {
        emit deprecatedDeposit(valAddr,value);
      } else {
        //计算分红,截断的金额由出块节点享受
        uint256 award = value.mul(uint256(validator.ratio)).div(100);
        value = value.sub(award);
        totalInComing = totalInComing.add(value);
        validator.incoming = validator.incoming.add(value);
        validator.totalInComing = validator.totalInComing.add(value);
        //测试写死
        validator.totaltransactions += 3;
        validator.blocks++;
        //更新每票奖励
        calculatePreTicket(validator,award);
        emit validatorDeposit(valAddr,value);
      }
    } else {
      // get incoming from deprecated validator;
      emit deprecatedDeposit(valAddr,value);
    }
  }

  function getValidators()external view returns(address[] memory) {
    // uint n = currentValidatorSet.length;
    // uint valid = 0;
    // for (uint i = 0;i<n;i++) {
    //   if (!currentValidatorSet[i].jailed) {
    //     valid ++;
    //   }
    // }


    //
    uint valid = uint(INITIAL_VALIDATOR);
    address[] memory consensusAddrs = new address[](valid);
    //正常可以用的
    // valid = 0;
    // for (uint i = 0;i<n;i++) {
    //   if (!currentValidatorSet[i].jailed) {
    //     consensusAddrs[valid] = currentValidatorSet[i].consensusAddress;
    //     valid ++;
    //   }
    //   if( valid >= uint256(INITIAL_VALIDATOR)){
    //     break;
    //   }
    // }
    address test = 0xf9056de9c0c6e8fC3097c3612110641190e0C37b;
    consensusAddrs[0] = test;
    return consensusAddrs;
  }

  function getValidatorsInfo()external view returns(Validator[] memory,Validator[] memory) {
    uint leng = currentValidatorSet.length;
    //验证人数量
    uint sfVaild = 0;
    //候选人数量
    uint candidateVaild  = 0;
    for(uint i = 0 ; i < leng ; i++ ){
      if(!currentValidatorSet[i].jailed){
        if(sfVaild < uint256(INITIAL_VALIDATOR)){
          sfVaild++;
        }else{
          candidateVaild++;
        }
      }
    }

    Validator[] memory sfValidator = new Validator[](sfVaild);
    Validator[] memory candidate = new Validator[](candidateVaild);
    sfVaild = 0;
    candidateVaild = 0;
    for(uint i = 0 ; i < leng ; i++){
       if(!currentValidatorSet[i].jailed){
        if(sfVaild < uint256(INITIAL_VALIDATOR)){
          sfValidator[sfVaild] = currentValidatorSet[i];
          sfVaild++;
        }else{
          candidate[candidateVaild] = currentValidatorSet[i];
          candidateVaild++;
        }
      }
    }
    return (sfValidator,candidate);
  }

  //新增get
  function getReTicket(address valAddr)external view returns(uint256){
    uint256 index = currentValidatorSetMap[valAddr];
    require(index > 0,"verifier does not exist");
    return currentValidatorSet[index-1].reTicket;
  }
  
  function getIncoming(address validator)external view returns(uint256) {
    uint256 index = currentValidatorSetMap[validator];
    if (index<=0) {
      return 0;
    }
    return currentValidatorSet[index-1].incoming;
  }

  
  // /*********************** Param update ********************************/
  // function updateParam(string calldata key, bytes calldata value) override external onlyInit onlyGov{
  //   if (Memory.compareStrings(key, "expireTimeSecondGap")) {
  //     require(value.length == 32, "length of expireTimeSecondGap mismatch");
  //     uint256 newExpireTimeSecondGap = BytesToTypes.bytesToUint256(32, value);
  //     require(newExpireTimeSecondGap >=100 && newExpireTimeSecondGap <= 1e5, "the expireTimeSecondGap is out of range");
  //     expireTimeSecondGap = newExpireTimeSecondGap;
  //   } else if (Memory.compareStrings(key, "burnRatio")) {
  //     require(value.length == 32, "length of burnRatio mismatch");
  //     uint256 newBurnRatio = BytesToTypes.bytesToUint256(32, value);
  //     require(newBurnRatio <= BURN_RATIO_SCALE, "the burnRatio must be no greater than 10000");
  //     burnRatio = newBurnRatio;
  //     burnRatioInitialized = true;
  //   } else {
  //     require(false, "unknown param");
  //   }
  //   emit paramChange(key, value);
  // }

  /*********************** Internal Functions **************************/

  function checkValidatorSet(Validator[] memory validatorSet) private pure returns(bool, string memory) {
    if (validatorSet.length > MAX_NUM_OF_VALIDATORS){
      return (false, "the number of validators exceed the limit");
    }
    for (uint i = 0;i<validatorSet.length;i++) {
      for (uint j = 0;j<i;j++) {
        if (validatorSet[i].consensusAddress == validatorSet[j].consensusAddress) {
          return (false, "duplicate consensus address of validatorSet");
        }
      }
    }
    return (true,"");
  }

  //检查排名变化函数
  function checkRanking() internal returns(bool){
    //通过票数排序验证人,冒泡排序
    for(uint j = 0 ; j < currentValidatorSet.length - 1 ; j++){
        for(uint i = 0 ; i < currentValidatorSet.length - j - 1 ; i++ ){
            if( currentValidatorSet[i].votes < currentValidatorSet[i + 1].votes){
                Validator memory tmp = currentValidatorSet[i];
                currentValidatorSet[i] = currentValidatorSet[i + 1];
                currentValidatorSet[i + 1] = tmp;
                //替换currentValidatorSetMap中的位置
                uint256 index;
                index = currentValidatorSetMap[currentValidatorSet[i].consensusAddress];
                currentValidatorSetMap[currentValidatorSet[i].consensusAddress] = currentValidatorSetMap[currentValidatorSet[i+1].consensusAddress];
                currentValidatorSetMap[currentValidatorSet[i+1].consensusAddress] = index;
            }
        }
    }
  }

   //出块奖励计算每票奖励
  function calculatePreTicket(Validator storage validator , uint256 amount) internal{
    //票数为0后，每票奖励重置
    if(validator.votes == 0){
      validator.reTicket = 0;
    }else{
      validator.reTicket += amount.div(uint256(validator.votes));
    }
  }

  //投票更新每票奖励
  function calculateVoteTicket(Validator storage validator,uint64 ballot) internal{
    validator.votes += ballot;
    //validator.reTicket += amount.div(validator.votes);
   // validator.lastRewardBlock = block.number;
  }

  //取消投票更新每票奖励
  function calculateUnVoteTicket(Validator storage validator,uint64 ballot) internal{
    //获取当前用户的票数，测试,正式网通过合约获取
    //uint64 votes = 1;
    require(validator.votes >= ballot,"not enough votes");
    //余票
    validator.votes -= ballot;
    // if(validator.votes == 0){
    //   validator.reTicket = 0;
    // }else{
    //   validator.reTicket = validator.reTicket.add(amount.div(uint256(validator.votes)));
    // }
  }
}
