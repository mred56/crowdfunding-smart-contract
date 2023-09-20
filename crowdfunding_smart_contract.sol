// SPDX-License-Identifier: Unlicense

pragma solidity ^0.8.0;

// Helps against reentrancy attacks    
import "https://github.com/OpenZeppelin/openzeppelin-contracts/blob/master/contracts/security/ReentrancyGuard.sol";

// SafeMath
import "https://github.com/OpenZeppelin/openzeppelin-contracts/blob/master/contracts/utils/math/SafeMath.sol";


contract crowdfundingContract is ReentrancyGuard{
    // projectID counter
    uint256 private counter;
    // Minimal fee for creating a new project
    uint256 private MIN_PROJECT_FEE = 1000000000000000 wei;

    // Use the SafeMath library for uint256 arithmetic
    using SafeMath for uint256;
    

    // Project registration template
    struct crowdfundingProject{
        uint256 projectID;
        string projectTitle;
        string projectDescription;
        address projectOwner;
        // fixed amount a participant has to contribute to a project to successfully participate
        uint256 projectParticipationAmount; 
        // total funding amount collected so far for that project. At the project creation this amount should be set to 0
        uint256 projectTotalFundingAmount; 
        // the amount of unclaimed funds in the smart contract
        uint256 projectFundsInSmartContract; 
        // The goal which has to be reached so that funds can be claimed
        uint256 projectFundingGoal; 
    }


    // All projects
    crowdfundingProject[] allProjects;


    // Mapping of participants' addreesses and their contributions in projects
    mapping(uint256 => mapping(address => uint256)) private projectsParticipants;

    // Used to iterate over the projectsParticipants mapping
    mapping(uint256 => address[]) projectsParticipantsIterate;


    // Constructor
    constructor(){
        counter = 0;
    }


    // Create a new project
    function createProject(string memory _projectTitle, string memory _projectDescription, uint256 _projectParticipationAmount, uint256 _projectFundingGoal) public payable{
        require(msg.value >= MIN_PROJECT_FEE, "You must pay at least MIN_PROJECT_FEE (0.001) ether to create a new project");
        require(bytes(_projectTitle).length > 0, "Project title cannot be empty");
        require(bytes(_projectDescription).length > 0, "Project description cannot be empty");
        require(_projectParticipationAmount > 0 && _projectParticipationAmount < 1e18, "Participation amount must be greater than 0 and less than 1e18");
        
        // Initialize the rest of the variables 
        uint256 _projectID = counter.add(1);
        address _projectOwner = msg.sender;
        uint256 _projectTotalFundingAmount = 0;
        uint256 _projectFundsInSmartContract = 0;

        // Create a new project and push it to the array of all projects
        crowdfundingProject memory newProject = crowdfundingProject(_projectID, _projectTitle, _projectDescription, _projectOwner, _projectParticipationAmount, _projectTotalFundingAmount, _projectFundsInSmartContract, _projectFundingGoal);
        allProjects.push(newProject);
    }
    

    // Contribute to a project
    function participateToProject(uint256 _projectID) public payable nonReentrant{
        require(_projectID <= allProjects.length, "The project ID does not exist");
        require(allProjects[_projectID - 1].projectParticipationAmount == msg.value, "You have to put in the exact participation amount as stated in the projectParticipationAmount");
        
        // Increse the contribution of a participant
        projectsParticipants[_projectID][msg.sender] += msg.value;
        // Add the participant for mapping iteration
        projectsParticipantsIterate[_projectID].push(msg.sender);
        // Increase the total funding amount
        allProjects[_projectID - 1].projectTotalFundingAmount += msg.value;
        //Increase the claimable funds in the smart contract
        allProjects[_projectID - 1].projectFundsInSmartContract += msg.value;
    }


    // Get project details
    function searchForProject(uint256 _projectID) public view returns(crowdfundingProject memory){
        require(_projectID <= allProjects.length, "The project ID does not exist");
        return allProjects[_projectID - 1];
    }


    // See the contributions made from a specific Ethereum address to a specific project
    function retrieveContributions(uint256 _projectID, address participantAddress) public view returns(uint256){
        require(_projectID <= allProjects.length, "The project ID does not exist");
        
        // Return 0 if the provided address does not exist in the mapping
        if(projectsParticipants[_projectID][participantAddress] > 0){
            return projectsParticipants[_projectID][participantAddress];
        }
        else{
            return 0;
        }
                
    }


    // Widthdrawal function, protected against a reentrancy attack
    function widthdrawFunds(uint256 _projectID) public nonReentrant{
        require(_projectID <= allProjects.length, "The project ID does not exist");
        require(msg.sender == allProjects[_projectID - 1].projectOwner, "You are not the project owner");
        require(allProjects[_projectID - 1].projectTotalFundingAmount >= allProjects[_projectID - 1].projectFundingGoal, "You have not reached your funding goal yet");
        
        // Transfer the funds to the owner 
        payable(msg.sender).transfer(allProjects[_projectID - 1].projectTotalFundingAmount);
        // Reset the projectFundsInSmartContract variable
        allProjects[_projectID - 1].projectFundsInSmartContract = 0;
    }


    // Refund contributors if the project has not reached its funding goal
    function refundContributions(uint256 _projectID) public {
        require(_projectID <= allProjects.length, "The project ID does not exist");
        require(msg.sender == allProjects[_projectID - 1].projectOwner, "You are not the project owner");
        // Add check to ensure project has not reached its funding goal
        require(allProjects[_projectID - 1].projectTotalFundingAmount < allProjects[_projectID - 1].projectFundingGoal, "The project has already reached its funding goal and cannot be refunded");

        // Iterate through the participants in the project and refund their contributions
        for (uint256 i = 0; i < projectsParticipantsIterate[_projectID].length; i++) {
            // Transfer the participant's contribution back to them
            payable(projectsParticipantsIterate[_projectID][i]).transfer(projectsParticipants[_projectID][projectsParticipantsIterate[_projectID][i]]);
            projectsParticipants[_projectID][projectsParticipantsIterate[_projectID][i]] = 0;
        }
        // Reset the total funding amount for the project to 0
        allProjects[_projectID - 1].projectTotalFundingAmount = 0;
        allProjects[_projectID - 1].projectFundsInSmartContract = 0;
    }

    // Refund your contribution from the project if you no longer want to participate
    function widthdrawYourContribution(uint256 _projectID) public nonReentrant{
        require(_projectID <= allProjects.length, "The project ID does not exist");
        require(projectsParticipants[_projectID][msg.sender] > 0, "You have not contributed to the project");
        require(allProjects[_projectID - 1].projectFundsInSmartContract >= projectsParticipants[_projectID][msg.sender], "Your funds have already been claimed by the project owner");

        // Transfer funds to the contributor
        payable(msg.sender).transfer(projectsParticipants[_projectID][msg.sender]);
        
        // Update projectFundsInSmartContract and projectTotalFundingAmount
        allProjects[_projectID - 1].projectFundsInSmartContract -= projectsParticipants[_projectID][msg.sender];
        allProjects[_projectID - 1].projectTotalFundingAmount -= projectsParticipants[_projectID][msg.sender];
        
        // Reset the contribution
        projectsParticipants[_projectID][msg.sender] = 0;
    }

}

