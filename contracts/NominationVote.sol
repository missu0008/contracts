pragma solidity 0.6.4;
pragma experimental ABIEncoderV2;

import "./lib/Memory.sol";
import "./lib/BytesToTypes.sol";
import "./System.sol";
import "./lib/SafeMath.sol";
import "./lib/RLPDecode.sol";
import "./lib/CmnPkg.sol";
import "./BSCValidatorSet.sol";

//提名投票设计思路

/*
    1.合约初始化后从验证人集合拿取验证人合约数据，初始化当前验证人表（原字段上加一个投票数，验证人数量）
    2.用户质押代币，通过质押的代币获取票数
    3.用户投票表，记录票数，当票数排名有变化时，调用验证人合约更新验证人的接口
*/

contract NominationVote is System {

    using RLPDecode for *;
    using SafeMath for uint256;

    //仅做简单的备份
    struct Validator{
        address consensusAddress;
        // only in state
        bool jailed;
    }
    
    //投票信息表
    struct VoterInfo{
        //票数
        uint64 votes;
        //债务
        uint256 debt;
    }

    //投票人资产信息表
    struct VoterIncome{
        //质押锁定的代币
        uint256 lockAmount;
        //累计收益
        uint256 totalAmount;
        //释放中的收益
        ThawInfo[] thawInfo;
        //已质押的代币
        uint256 usedLockAmount;
    }

    //解冻信息
    struct ThawInfo{
        //解冻金额
        uint256 amount;
        //解冻开始时间
        uint startTime;
    }

    //质押总量
    uint256 public TOTAL_PLEDGE = 0;

    //代币精度 ， 1代币 = 1票，禁止分割,bsc链上精度为18
    uint256 public constant TOKEN_PRECISION = 1000000000000000000;
    //成为验证候选人抵押代币数量,测试至少为10个，remix账号上面只有100个。。。
    uint256 public constant TOKEN_CANDIDATE = 10000000000000000000;
    //解冻周期,测试时间1800s
    uint public THAW_CYCLE = 1800; // * 24 * 3;
    //成为验证人抵押的代币数量
    mapping(address => uint256) public userToken;
    //取消成为验证人冻结的信息
    mapping(address => ThawInfo) public userInfo;

    //最大验证人数量
    uint256 public constant MAX_NUM_OF_VALIDATORS = 41;
    //验证人信息表
    Validator[] public currentValidatorSet;
    
    mapping(address =>uint256) public currentValidatorSetMap;
    //投票人的表 1GST = 1票
    mapping(address => mapping(address => VoterInfo)) public voter;
    //投票人质押信息
    mapping(address => VoterIncome) public userGst;

    BSCValidatorSet bscValidatorSet;
    //测试
    address public constant TEST = 0xd9145CCE52D386f254917e481eB44e9943F39138;


    /*********************** init 初始化函数主要是获取验证人集合，和BSCValidatorSet中保持一致**************************/
    function init() external onlyNotInit{
        Validator memory validator;
        validator.consensusAddress = GENESIS_NODE;
        currentValidatorSet.push(validator);
        currentValidatorSetMap[GENESIS_NODE] = 1;
        bscValidatorSet = BSCValidatorSet(VALIDATOR_CONTRACT_ADDR);
        alreadyInit = true;
    }

    //质押代币
    function pledgeGst() external payable onlyInit returns(uint256){
        require( msg.value > 0 ,"please input value");
        address user = msg.sender;
        uint256 tokenamount = msg.value;
        checkAmount(tokenamount);
        userGst[user].lockAmount = userGst[user].lockAmount.add(tokenamount);
        TOTAL_PLEDGE = TOTAL_PLEDGE.add(tokenamount);
        return tokenamount;
    }

    //取消质押代币
    function unpledgeGst(uint256 amount) external onlyInit {
        require(amount > 0 ,"amount must be greater than 0");
        checkAmount(amount);
        //已投票数,换算成和gst 1:1
       // uint256 voted = 0;
        //质押的总代币
        uint256 total_gst = userGst[msg.sender].lockAmount;
        require(total_gst > 0 ,"tokens not yet pledged");
       // voted = getUserVoted(msg.sender);
        require(total_gst.sub(userGst[msg.sender].usedLockAmount) >= amount ,"some GST have been voted" );
        require(address(this).balance >= amount,"insufficient contract balance");
        userGst[msg.sender].lockAmount = userGst[msg.sender].lockAmount.sub(amount);

        //待返回的钱进入解冻周期
        ThawInfo memory thawinfo;
        thawinfo.amount = amount;
        thawinfo.startTime = block.timestamp;
        userGst[msg.sender].thawInfo.push(thawinfo);
         TOTAL_PLEDGE = TOTAL_PLEDGE.sub(amount);
        //msg.sender.transfer(amount);
    }

    //领取取消质押的代币
    function retrieveGst() external onlyInit{
        uint256 amount;
        uint nowTime = block.timestamp;
        uint valid = 0;
        for(uint i = 0 ; i < userGst[msg.sender].thawInfo.length ; i ++){
            if( nowTime - THAW_CYCLE >= userGst[msg.sender].thawInfo[i].startTime){
                valid++;
            }
        }
        require(valid > 0 ,"no gst tokens to claim");
        //冒泡排序，质押代币按时间从小到大
        for(uint j = 0 ; j < userGst[msg.sender].thawInfo.length - 1 ; j++){
            for(uint i = 0 ; i <userGst[msg.sender].thawInfo.length - j - 1 ; i++ ){
                if( userGst[msg.sender].thawInfo[i].startTime > userGst[msg.sender].thawInfo[i + 1].startTime){
                    ThawInfo memory tmp = userGst[msg.sender].thawInfo[i];
                    userGst[msg.sender].thawInfo[i] = userGst[msg.sender].thawInfo[i + 1];
                    userGst[msg.sender].thawInfo[i + 1] = tmp;
                }
            }
        }
        //满足条件的计算出数量后删除
        for(uint i = 0 ; i < valid ; i++){
            uint index = userGst[msg.sender].thawInfo.length - 1;
            amount = amount.add(userGst[msg.sender].thawInfo[index].amount);
            userGst[msg.sender].thawInfo.pop();
        }
        msg.sender.transfer(amount);
    }


    //给验证人投票
    function voteVerifier(uint64[] memory ballot , address[] memory verificationNode) public onlyInit{
        require(ballot.length == verificationNode.length && ballot.length > 0 ,"parameter error");
        uint length = ballot.length;
        for(uint i = 0 ; i < length ; i++){
            require(ballot[i] > 0 , "the number of votes must be greater than 0");
            //已投票数
            uint256 voted = 0;
            voted = getUserVoted(msg.sender);
            uint256 remain_vote = userGst[msg.sender].lockAmount.sub(voted);
            require(remain_vote.sub(uint256(ballot[i]).mul(TOKEN_PRECISION)) >= 0 ,"insufficient votes");

            //获取每票奖励
            uint256 reTicket = bscValidatorSet.getReTicket(verificationNode[i]);
            //更新债务
            //第一次投票
            if(voter[msg.sender][verificationNode[i]].votes == 0 ){
                voter[msg.sender][verificationNode[i]].debt = reTicket.mul(uint256(ballot[i]));
            }else{
                voter[msg.sender][verificationNode[i]].debt = voter[msg.sender][verificationNode[i]].debt.add(reTicket.mul(uint256(ballot[i])));
            }
            //更新用户投票信息
            //voter[msg.sender][verificationNode] = voter[msg.sender][verificationNode].add(ballot);
            voter[msg.sender][verificationNode[i]].votes += ballot[i];

            bscValidatorSet.updateVoter(ballot[i], verificationNode[i], true);
        }
    }

    //取消对验证节点投票的票数
    function unvoterVerifier(uint64[] memory ballot , address[] memory verificationNode) public onlyInit{
        require(ballot.length == verificationNode.length && ballot.length > 0 ,"parameter error");
 
        uint length = ballot.length;
        for(uint i = 0 ; i < length ; i++){
            require(ballot[i] > 0 , "the number of votes must be greater than 0");
            require(voter[msg.sender][verificationNode[i]].votes >= ballot[i],"insufficient number of revoked votes");  
            
            //获取每票奖励
            uint256 reTicket = bscValidatorSet.getReTicket(verificationNode[i]);

            uint256 reward = uint256(voter[msg.sender][verificationNode[i]].votes).mul(reTicket).sub(voter[msg.sender][verificationNode[i]].debt);
            //把这笔钱转给投票人
            bscValidatorSet.withdrawGst(msg.sender , reward );
            //累计收益增加
            userGst[msg.sender].totalAmount = userGst[msg.sender].totalAmount.add(reward);
            //如果有余票，当做新用户计算债务
            if(voter[msg.sender][verificationNode[i]].votes > 0){
                voter[msg.sender][verificationNode[i]].debt = reTicket.mul(uint256(voter[msg.sender][verificationNode[i]].votes));
            }else{
                voter[msg.sender][verificationNode[i]].debt = 0;
            }

            //更新验证人表中的票数
            voter[msg.sender][verificationNode[i]].votes -= ballot[i];
            //更新验证人合约总票数
            bscValidatorSet.updateVoter(ballot[i], verificationNode[i], false);
        }
    }

    //申请成为验证候选人
    function validateCandidates(int8 ratio) external payable onlyInit{
        require(msg.value >= TOKEN_CANDIDATE, "insuffibcient mortgage tokens");
        require(ratio >= 0 && ratio <= 100 ,"must be between 0-100");
        //取消成为验证人期间禁止再次成为验证人
        require(userInfo[msg.sender].startTime == 0, "取消成为验证人有十五天的冻结期，请领取上次质押的代币再重新竞选" );
        bscValidatorSet.updateCandidates(msg.sender,ratio);
        userToken[msg.sender] = msg.value;

        //查看缓存，缓存有直接改变状态
        bool flag = true;
        uint i = 0;
        uint256 n = currentValidatorSet.length;
        for(; i < n ; i++){
            if( currentValidatorSet[i].consensusAddress == msg.sender ){
                currentValidatorSet[i].jailed = false;
                flag = false;
                break;
            }
        }
        if(flag){
            Validator memory validator;
            validator.consensusAddress = msg.sender; 
            validator.jailed = false;
            currentValidatorSet.push(validator);
        }

        TOTAL_PLEDGE = TOTAL_PLEDGE.add(msg.value);

    }

    //取消成为验证候选人
    function unvalidateCandidates() external onlyInit{
        //判断当前用户是否是验证人
        bool flag = false;
        uint i = 0;
        uint256 n = currentValidatorSet.length;
        for ( ; i < n ; i++){
            if( currentValidatorSet[i].consensusAddress == msg.sender ){
                flag = true;
                currentValidatorSet[i].jailed = true;
                break;
            }
        }
        require(flag, "not a candidate");
        bscValidatorSet.cancleCandidates(msg.sender);
        userInfo[msg.sender].amount = userToken[msg.sender];
        userInfo[msg.sender].startTime = block.timestamp;
    }

    function receiveValidateGST()external onlyInit{
        uint nowTime = block.timestamp;
        require(userInfo[msg.sender].startTime > 0, "pledge does not exist" );
        require(nowTime - userInfo[msg.sender].startTime > THAW_CYCLE , "not yet time!!");
        //退钱
        msg.sender.transfer(userInfo[msg.sender].amount);
        //总质押量减少
        TOTAL_PLEDGE = TOTAL_PLEDGE.sub(userInfo[msg.sender].amount);
        delete userInfo[msg.sender];
    }

    //投票人领取分红奖励
    function receiveAward(uint256 awardGst)external onlyInit{
        uint256 maxAward = getIncome(msg.sender);
        require(maxAward >= awardGst , "insufficient reward GST");
        //累积的money
        uint256 amount;

        //看其是否有出块奖励
        amount = bscValidatorSet.getIncoming(msg.sender);
        //领取收益的是验证人，优先拿取出块奖励
        if(amount > 0){
            bscValidatorSet.withdrawValidatorGst(msg.sender,amount);
            if(amount >= awardGst){
                bscValidatorSet.withdrawGst(msg.sender , awardGst );
                return;
            }
        }
        //遍历验证人表
        uint length = currentValidatorSet.length;
        for(uint i = 0 ; i < length ; i++){
            if(voter[msg.sender][currentValidatorSet[i].consensusAddress].votes > 0){
                uint256 reTicket = bscValidatorSet.getReTicket(currentValidatorSet[i].consensusAddress);
                uint256 reward = uint256(voter[msg.sender][currentValidatorSet[i].consensusAddress].votes).mul(reTicket).sub(voter[msg.sender][currentValidatorSet[i].consensusAddress].debt);
                amount = amount.add(reward);
                if( amount >= awardGst){
                    reward = amount.sub(awardGst);
                    //更新债务
                    voter[msg.sender][currentValidatorSet[i].consensusAddress].debt = voter[msg.sender][currentValidatorSet[i].consensusAddress].debt.add(reward);
                    break;
                }else{
                    //更新债务
                    voter[msg.sender][currentValidatorSet[i].consensusAddress].debt.add(reward);
                }
            }
        }
        //累计收益增加
        userGst[msg.sender].totalAmount = userGst[msg.sender].totalAmount.add(awardGst);
        //打钱
        bscValidatorSet.withdrawGst(msg.sender , awardGst );

    }

    //判断精度是否为18的整数
    function checkAmount(uint256 amount) internal pure{
        require(amount % TOKEN_PRECISION == 0 , "must be an integer");
    }

    //获取当前用户已投票的总票数
    function getUserVoted(address user) internal view returns(uint256){
        //判断用户是否已投过票
        uint n = currentValidatorSet.length;
        uint256 voted = 0;
        for (uint i = 0;i<n;i++) {
            Validator memory validator = currentValidatorSet[i];
            voted = voted.add(uint256(voter[user][validator.consensusAddress].votes));
        }
        voted = voted.mul(TOKEN_PRECISION);
        return voted;
    }

    /****************************get function ****************************************/
    //获取该用户的总收益(出块奖励 + 投票收益)
    function getIncome(address user) public view returns(uint256){
        uint256 income = 0;
        //遍历验证人表
        uint length = currentValidatorSet.length;
        for(uint i = 0 ; i < length ; i++){
            if(voter[user][currentValidatorSet[i].consensusAddress].votes > 0){
                uint256 reTicket = bscValidatorSet.getReTicket(currentValidatorSet[i].consensusAddress);
                uint256 reward = uint256(voter[user][currentValidatorSet[i].consensusAddress].votes).mul(reTicket).sub(voter[user][currentValidatorSet[i].consensusAddress].debt);
                income = income.add(reward);
            }
        }
        income = income.add(bscValidatorSet.getIncoming(user));
        return income;
    }

    //查询用户满足解冻以及正在释放中的资产额
    function getThawInfo(address user) external view returns(uint256,uint256){
        uint length = userGst[user].thawInfo.length;
        //满足解冻的金额
        uint256 amount = 0;
        //正在释放中的资产额
        uint256 releaseAmount = 0;
        uint time = block.timestamp;
       
        for(uint i = 0 ; i < length ; i++){
            //thawInfo[i] = userGst[user].thawInfo[i]
            if( time - userGst[user].thawInfo[i].startTime >= THAW_CYCLE){
                amount = amount.add(userGst[user].thawInfo[i].amount);
            }else{
                releaseAmount = releaseAmount.add(userGst[user].thawInfo[i].amount);
            }
        }

        return (amount,releaseAmount);

    }

    //查询当前用户的票数
    function getVoteInfo(address user) public view returns(uint64[] memory, address[] memory){
        //获取当前验证人
        uint vaLength = currentValidatorSet.length;
        uint vaild = 0;
        //获取投票的节点数
        for(uint i = 0 ; i < vaLength ; i++){
            if(voter[user][currentValidatorSet[i].consensusAddress].votes > 0){
                vaild++;
            }
        }
        uint64[] memory votes = new uint64[](vaild);
        address[] memory voteAddress = new address[](vaild);

        uint j = 0;
        for(uint i = 0  ; i < vaLength ; i++){
            if(voter[user][currentValidatorSet[i].consensusAddress].votes > 0){
                votes[j] = voter[user][currentValidatorSet[i].consensusAddress].votes;
                voteAddress[j] = currentValidatorSet[i].consensusAddress;
                j++;
            }
        }

        return (votes,voteAddress);

    }
}