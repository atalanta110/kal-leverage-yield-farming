pragma solidity 0.5.16;
import "@openzeppelin/contracts/ownership/Ownable.sol";
import "@openzeppelin/contracts/math/SafeMath.sol";
import "@openzeppelin/contracts/utils/ReentrancyGuard.sol";
import "@uniswap/v2-core/contracts/interfaces/IUniswapV2Factory.sol";
import "@uniswap/v2-core/contracts/interfaces/IUniswapV2Pair.sol";
import "@uniswap/v2-core/contracts/libraries/Math.sol";
import "./bakeswap/IBakerySwapRouter.sol";
import "./SafeToken.sol";
import "./Strategy.sol";


contract StrategyAllBNBOnlyBake is Ownable, ReentrancyGuard, Strategy {
    using SafeToken for address;
    using SafeMath for uint256;

    IUniswapV2Factory public factory;
    IBakerySwapRouter public router;
    address public wbnb;

    /// @dev Create a new add ETH only strategy instance.
    /// @param _router The Uniswap router smart contract.
    constructor(IBakerySwapRouter _router) public {
        factory = IUniswapV2Factory(_router.factory());
        router = _router;
        wbnb = _router.WBNB();
    }

    /// @dev Execute worker strategy. Take LP tokens + ETH. Return LP tokens + ETH.
    /// @param data Extra calldata information passed along to this strategy.
    function execute(address /* user */, uint256 /* debt */, bytes calldata data)
        external
        payable
        nonReentrant
    {
        // 1. Find out what farming token we are dealing with and min additional LP tokens.
        (address fToken, uint256 minLPAmount) = abi.decode(data, (address, uint256));
        IUniswapV2Pair lpToken = IUniswapV2Pair(factory.getPair(fToken, wbnb));
        // 2. Compute the optimal amount of ETH to be converted to farming tokens.
        uint256 balance = address(this).balance;
        (uint256 r0, uint256 r1, ) = lpToken.getReserves();
        uint256 rIn = lpToken.token0() == wbnb ? r0 : r1;
        uint256 aIn =
            Math.sqrt(rIn.mul(balance.mul(3988000).add(rIn.mul(3988009)))).sub(rIn.mul(1997)) / 1994;
        // 3. Convert that portion of ETH to farming tokens.
        address[] memory path = new address[](2);
        path[0] = wbnb;
        path[1] = fToken;
        router.swapExactBNBForTokens.value(aIn)(0, path, address(this), now);
        // 4. Mint more LP tokens and return all LP tokens to the sender.
        fToken.safeApprove(address(router), 0);
        fToken.safeApprove(address(router), uint(-1));
        (,, uint256 moreLPAmount) = router.addLiquidityBNB.value(address(this).balance)(
            fToken, fToken.myBalance(), 0, 0, address(this), now
        );
        require(moreLPAmount >= minLPAmount, "insufficient LP tokens received");
        lpToken.transfer(msg.sender, lpToken.balanceOf(address(this)));
    }

    /// @dev Recover ERC20 tokens that were accidentally sent to this smart contract.
    /// @param token The token contract. Can be anything. This contract should not hold ERC20 tokens.
    /// @param to The address to send the tokens to.
    /// @param value The number of tokens to transfer to `to`.
    function recover(address token, address to, uint256 value) external onlyOwner nonReentrant {
        token.safeTransfer(to, value);
    }

    function() external payable {}
}
