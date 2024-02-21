// SPDX-License-Identifier: Unlicense

pragma solidity ^0.8.19;

import {LinkTokenInterface} from "@chainlink/contracts/src/v0.8/interfaces/LinkTokenInterface.sol";
import {IERC20} from "@chainlink/contracts-ccip/src/v0.8/vendor/openzeppelin-solidity/v4.8.0/contracts/token/ERC20/IERC20.sol";
import {SafeERC20} from "@chainlink/contracts-ccip/src/v0.8/vendor/openzeppelin-solidity/v4.8.0/contracts/token/ERC20/utils/SafeERC20.sol";
import {IRouterClient} from "@chainlink/contracts-ccip/src/v0.8/ccip/interfaces/IRouterClient.sol";
import {Client} from "@chainlink/contracts-ccip/src/v0.8/ccip/libraries/Client.sol";

contract CCIPTokenSender is OwnerIsCreator {
    using SafeERC20 for IERC20;

    event MessageSent(bytes32 messageId);
    error FailedToWithdrawEth(address owner, address target, uint256 value);

    enum PayFeesIn {
        Native,
        LINK
    }

    address immutable i_router;
    address immutable i_link;

    constructor(address router, address link) {
        i_router = router;
        i_link = link;
    }

    receive() external payable {}

    function sendToken(
        address tokenAddress,
        address receiver,
        uint64 destinationChainSelector,
        uint256 amount
    ) external returns (bytes32 messageId) {
        SafeERC20(tokenAddress).burnFrom(msg.sender, amount);

        Client.EVM2AnyMessage memory message = Client.EVM2AnyMessage({
            receiver: abi.encode(receiver),
            data: abi.encode(amount, receiver),
            tokenAmounts: new Client.EVMTokenAmount[](0), // we only send the message
            extraArgs: "",
            feeToken: address(0) // pay fee in gas
        });

        uint256 fee = IRouterClient(i_router).getFee(
            destinationChainSelector,
            message
        );

        bytes32 messageId;

        messageId = IRouterClient(i_router).ccipSend{value: fee}(
            destinationChainSelector,
            message
        );

        emit MessageSent(messageId);
    }

    function withdraw(address beneficiary) public onlyOwner {
        uint256 amount = address(this).balance;
        (bool sent, ) = beneficiary.call{value: amount}("");
        if (!sent) revert FailedToWithdrawEth(msg.sender, beneficiary, amount);
    }

    function withdrawToken(
        address beneficiary,
        address token
    ) public onlyOwner {
        uint256 amount = IERC20(token).balanceOf(address(this));
        IERC20(token).safeTransfer(beneficiary, amount);
    }
}
