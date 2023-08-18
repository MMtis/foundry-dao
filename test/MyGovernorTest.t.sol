// SPDX-License-Identifier: MIT

pragma solidity ^0.8.18;

import {Test, console} from "forge-std/Test.sol";
import {MyGovernor} from "src/MyGovernor.sol";
import {Box} from "src/Box.sol";
import {TimeLock} from "src/TimeLock.sol";
import {GovToken} from "src/GovToken.sol";

contract MyGovernorTest is Test {
    MyGovernor governor;
    Box box;
    TimeLock timeLock;
    GovToken govToken;

    address public USER = makeAddr("user");
    uint256 public constant INITIAL_SUPPLY = 100 ether;

    uint256 public constant MIN_DELAY = 3600; // 1 hour - delay after a vote passes
    uint256 public constant VOTING_DELAY = 7200; // how manay blocks till a vote is active
    uint256 public constant VOTING_PERIOD = 50400;

    address[] proposers;
    address[] executers;
    uint256[] values;
    bytes[] calldatas;
    address[] targets;

    function setUp() public {
        govToken = new GovToken();
        govToken.mint(USER, INITIAL_SUPPLY);

        vm.startPrank(USER);
        govToken.delegate(USER); // the function _moveVotingPower of the ERC20Votes contract is called only by
            // the functions _delegate and _afterTokenTransfer which are internal
        timeLock = new TimeLock(MIN_DELAY, proposers, executers); // by leaving proposers and executers blank
            // that's how we tell timelock that everybody can propose and execute
        governor = new MyGovernor(govToken, timeLock);

        bytes32 proposerRole = timeLock.PROPOSER_ROLE();
        bytes32 executorRole = timeLock.EXECUTOR_ROLE();
        bytes32 adminRole = timeLock.TIMELOCK_ADMIN_ROLE();

        timeLock.grantRole(proposerRole, address(governor)); // only the governor can propose
        timeLock.grantRole(executorRole, address(0)); // Anybody can execute --> modifier onlyRoleOrOpenRole
        timeLock.revokeRole(adminRole, USER); // the user is not the admin anymore
        vm.stopPrank();

        box = new Box();
        box.transferOwnership(address(timeLock));
    }

    function testCanUpdateBoxWithoutGovernance() public {
        vm.expectRevert();
        box.store(1);
    }

    function testGovernanceUpdatesBox() public {
        uint256 valueToStore = 888;
        string memory description = "store 1 in Box";
        bytes memory encodedFunctionCall = abi.encodeWithSignature("store(uint256)", valueToStore);

        values.push(0);
        calldatas.push(encodedFunctionCall);
        targets.push(address(box));

        // 1. Propose to the DAO
        uint256 proposalId = governor.propose(targets, values, calldatas, description);

        // View the state
        console.log("Proposal state: %s", uint256(governor.state(proposalId)));

        vm.warp(block.timestamp + VOTING_DELAY + 1); // No need for this one
        vm.roll(block.number + VOTING_DELAY + 1); // if (snapshot >= currentTimepoint) this condition is false

        console.log("Proposal state: %s", uint256(governor.state(proposalId)));

        // 2. Vote
        string memory reason = "cuz blue frog is cool";

        uint8 voteWay = 1; // voting yes
        vm.prank(USER);
        governor.castVoteWithReason(proposalId, voteWay, reason);

        vm.warp(block.timestamp + VOTING_PERIOD + 1);
        vm.roll(block.number + VOTING_PERIOD + 1); // if (deadline >= currentTimepoint) this condition is false
        // require(state(proposalId) == ProposalState.Succeeded

        // 3. Queue the TX
        bytes32 descriptionHash = keccak256(abi.encodePacked(description));
        // abi.encode
        // When you use abi.encode(), you are using Ethereum's Application Binary Interface (ABI) to encode data.
        // This encoding is more structured and is meant to encode not only the value but also the type and
        // sometimes the location of the data, so that it can be correctly
        // Example : abi.ecode("HELLO") : Result has 96 bytes
        // Let's break down the result:
        // 0x0000000000000000000000000000000000000000000000000000000000000020: This is a 32-byte value
        // representing the offset (in bytes) to the location of the data. For a string, the data starts
        // after this 32-byte offset.
        // 0x0000000000000000000000000000000000000000000000000000000000000005: This is the length of the string
        // "HELLO", which is 5 characters.
        // 0x48454c4c4f000000000000000000000000000000000000000000000000000000: This is the actual data
        // (the string "HELLO"). Notice that after the "HELLO" part, it is right-padded with zeros to make
        // the total length a multiple of 32 bytes.
        // for other data types you don't need length specifiers

        // bytes()
        // When you do a direct conversion from a string to bytes using bytes(description), you are essentially
        // just converting the string to its raw byte representation. For the string "HELLO", the ASCII values
        // for each character are as follows:
        // 0x48454c4c4f

        // abi.encodePacked
        // This provides compact encoding without padding. When encoding a single string, it directly gives
        // the raw byte representation of the string without any added information or padding.
        // when you're dealing with multiple arguments or various data types. abi.encodePacked will
        // concatenate each of the encoded arguments back-to-back without any padding.
        // For a single string, it is the same as bytes()

        governor.queue(targets, values, calldatas, descriptionHash);
        // queue function of GovernorTimelockControl updates _timestamps mapping in TimelockController
        // in the function _schedule. _timestamps update is necessary to call the execute function
        // Because of the check: return timestamp > _DONE_TIMESTAMP && timestamp <= block.timestamp;

        vm.warp(block.timestamp + MIN_DELAY + 1);
        vm.roll(block.number + MIN_DELAY + 1);

        // 4. execute
        governor.execute(targets, values, calldatas, descriptionHash); // GovernorTimelockControl inherits from
        // Governor and will use the function execute of GovernorTimelockControl

        console.log("Box value", box.getNumber());
        assert(box.getNumber() == valueToStore);
    }
}
