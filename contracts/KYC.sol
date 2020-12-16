pragma solidity ^0.5.9;
// Using ABIEncoderV2 to return array of struct and struct object in gatBankDetails and getBankRequest in BankContract.
pragma experimental ABIEncoderV2;


//AdminContract to implement the admin interface methods. Used this approach to segregate admin and bank functionality.
contract AdminContract{
    
    address admin;
    uint noOfBanks;
    
    struct Bank {
		bytes32 Name;
		address ethAddress;
		uint Rating;
		uint KYC_count;
		bytes32 regNumber;
	} 
	
	// setting the address deploying the contract as admin
	constructor() public {
	    admin = msg.sender;
	    noOfBanks = 0;
	}
	
	// Mapping to store bank details and upvotes for a bank by other banks. Using bank address as the unique identifier.
	mapping (address => Bank) banks;
	mapping (address => address[]) banksUpvoted;

	// Events for admin functionality. Event emitted on success to monitor timestamp of action. 	
	event BankAdded(address indexed _bank,bytes32 indexed _name, uint256 _timestamp);
	event BankRemoved(address indexed _bank,bytes32 indexed _name, uint256 _timestamp);
	
	function AddBank (bytes32 _name,bytes32 _regNumber,address _bankAddress) isAdmin external returns(bool){
	    // checking if bank already exists in mapping, for non existing bank address value will be default "0". So checking if bank is already added.
		// Not handling data validations as they can be done on UI like regNumber should not be empty or incorrect format.
	    require(banks[_bankAddress].regNumber == 0 ,"BankAlreadyExists");
	    
	    banks[_bankAddress].Name = _name;
	    banks[_bankAddress].ethAddress = _bankAddress;
	    banks[_bankAddress].regNumber = _regNumber;
	    banks[_bankAddress].KYC_count = 0;
	    banks[_bankAddress].Rating = 0;
	    
	    noOfBanks ++;
	    
	    emit BankAdded(_bankAddress,_name,now);
	    return true;
	}
	
	function RemoveBank (address _bankAddress) isAdmin external returns(bool){
		// check to see if any bank exists in the system or the requested bank exists in the system
	    
	    require(noOfBanks > 0,"NoBanksAdded");
	    require(banks[_bankAddress].regNumber != 0 ,"BankDoesNotExist");
	    
        delete banks[_bankAddress];
        delete banksUpvoted[_bankAddress];
        
        noOfBanks --;
       
        emit BankRemoved(_bankAddress,banks[_bankAddress].Name,now);
	    return true;
	}
	
	// function modifier to check if sender of transaction is admin or not.
	modifier isAdmin() { 
	    require(admin == msg.sender,"NotAnAdmin");
		_;
	}
}

contract BankContract is AdminContract {

	struct Customer {
		bytes32 Username;
		bytes32 CustomerData;
		uint Upvotes; 
		uint Rating;
		address Bank;
	}

	struct KYCRequest{
		bytes32 Username;
		bytes32 CustomerData;
		address BankAddress;
		bool IsAllowed;
	}
	
	 /*
	 Created request array to store all the requests. As there can be multiple request with same username mapping(username => KYCRequest) was not possible.
	 mapping(username => customerdata => KYCRequest) made sense but there is no guarantee that data will be diffrent in other request for same username.
	 mapping(username => KYCRequest[]) was also an option but too fetch bank requests might need another mapping mapping(bankAddress => KYCRequest[]) as iterating on mapping is not possible.
	 */
	 /*
	 Understanding array usage makes system not scalable and two mapping can be used to cover all fuctionality but storage as the most costly factor decided to go with array currently.
	 */
	 
	KYCRequest[] requests;
	
	/*
	mapping for customers, final_customers, passwords and upvotes for a customer by banks. 
	Password can be part of Customer strut but made it a mapping as it was not instructed to make change in the struct.
	*/
	mapping (bytes32 => Customer) customers;
	mapping (bytes32 => Customer) final_customer;
	mapping (bytes32 => bytes32) passwords;
	mapping (bytes32 => address[]) upvotes;
	
	// Events to monitor activity of user for bank functionality affecting the state of data.
	event AddRequestEvent(address indexed _bank, bytes32 indexed _username, uint256 _timestamp);
	event RemoveRequestEvent(address indexed _bank, bytes32 indexed _username, uint256 _timestamp);
	event AddCustomerEvent(address indexed _bank, bytes32 indexed _username, uint256 _timestamp);
	event RemoveCustomerEvent(address indexed _bank, bytes32 indexed _username, uint256 _timestamp);
	event ModifyCustomerEvent(address indexed _bank, bytes32 indexed _username, uint256 _timestamp);
	event UpvoteCustomerEvent(bytes32 indexed _username, address indexed _votedBy, uint256 _timestamp);
	event UpvoteBankEvent(address indexed _bank, address indexed _votedBy, uint256 _timestamp);
	event SetPasswordEvent(address indexed _bank, bytes32 indexed _username, uint256 _timestamp);

	/*
	Formulating isAllowed based on bank rating. Setting isAllowed true for first bank request otherwise it will not be able to process or bank has to enter the request again to process.
	Functionality mentioned didn't provide any instruction to handle this or we have to give rating before processing any customer so that for those request isAllowed set to true for process.
	Considering it will receieve rating once few requests are process.
	*/ 
	function AddRequest (bytes32 _username,bytes32 _customerData) isBankValid external returns(uint) {
		bool isAllowed = false;
		if(banks[msg.sender].Rating > 50 || banks[msg.sender].KYC_count == 0){
		    isAllowed = true;
		}
		requests.push( KYCRequest(_username,_customerData,msg.sender,isAllowed) );
		banks[msg.sender].KYC_count++;
		emit AddRequestEvent(msg.sender,_username,now);
		return 1;
	}

	/*
	Removing all requests with that username when gets added as customer.
	*/
	function AddCustomer(bytes32 _username,bytes32 _customerData) isBankValid isCustomerAllowed(_username) external returns(uint) {
        require(customers[_username].CustomerData == 0,"CustomerWithTheSameUsernameAlreadyExists");
        RemoveAllRequest(_username);
        customers[_username].Username = _username;
        customers[_username].CustomerData  = _customerData;
        customers[_username].Upvotes = 0;
        customers[_username].Rating = 0;
        customers[_username].Bank = msg.sender;
        emit AddCustomerEvent(msg.sender,_username,now);
        return 1;
	}

	function RemoveAllRequest(bytes32 _username) internal {
        for(uint i=0; i<requests.length; i++){
            if(requests[i].Username == _username){
                delete requests[i];
            }
        }
	}
	
	// Understand that this is not scalable but considering requests will proccesed quickly and size will not grow out of hand.
	function RemoveRequest(bytes32 _username,bytes32 _customerData) isBankValid external returns (uint) {
	    bool requestExists = false;
	    for(uint i=0;i<requests.length;i++){
	        if(requests[i].Username == _username && requests[i].CustomerData == _customerData ){
                requestExists = true;
                delete requests[i];
	        }
	    }
        require(requestExists,"NoSuchRequestExists");
        emit RemoveRequestEvent(msg.sender,_username,now);
        return 1;
	}

	function RemoveCustomer(bytes32 _username) isBankValid isCustomerValid(_username) external returns (uint) {
        delete customers[_username];
        emit RemoveCustomerEvent(msg.sender,_username,now);
        return 1;
	}

	// Checking password. If not present in password mapping checking for default password. Removing customer from final list and all upvotes by banks.
	function ModifyCustomer(bytes32 _username,bytes32 _customerData,bytes32 _password) isBankValid isCustomerValid(_username) external returns(uint) {
        if(passwords[_username] != 0) {
	        require(passwords[_username] == _password,"IncorrectPassword");
	    } else {
	        require(_password == "0","IncorrectDefaultPassword");
	    }
	    UpdateFinalList(_username);
	    customers[_username].CustomerData  = _customerData;
        customers[_username].Upvotes = 0;
        customers[_username].Rating = 0;
        customers[_username].Bank = msg.sender;
        delete upvotes[_username];
        emit ModifyCustomerEvent(msg.sender,_username,now);
        return 1;
	}
	
    // internal fuction 
	function UpdateFinalList(bytes32 _username) internal {
	    if(final_customer[_username].CustomerData != 0){
	        delete final_customer[_username];
	    }
	}

	function viewCustomer(bytes32 _username,bytes32 _password) view public isBankValid isCustomerValid(_username) returns(bytes32){
	   if(passwords[_username] != 0) {
	        require(passwords[_username] == _password,"IncorrectPassword");
	    }
	    else{
	        require(_password == "0","IncorrectDefaultPassword");
	    }
		return customers[_username].CustomerData;
	}
	
	// Setting password in mapping using username as unique identifier.
	function setPassword(bytes32 _username,bytes32 _password) external isBankValid isCustomerValid(_username) returns(bool){
	    passwords[_username] = _password;
	    return true;
	}

	// Upvoting a customer. Checking if bank already upvoted in function modifier checkIfAlreadyUpvoted.
	// Pushing bank to array on mapping upvotes by username.
	// Calculating rating based on upvotes and number of banks and multiplying by 100. If required to show in decimal something which can be handled in UI so as to not handle decimal values in solidity.
	function upvote(bytes32 _username) isBankValid isCustomerValid(_username) checkIfAlreadyUpvoted(_username) external returns(uint isSuccess){
        customers[_username].Upvotes = customers[_username].Upvotes + 1;
        customers[_username].Rating = (customers[_username].Upvotes * 100 ) /noOfBanks ;
        if(customers[_username].Rating > 50){
            final_customer[_username] = customers[_username];
        }
        upvotes[_username].push(msg.sender);
        emit UpvoteCustomerEvent(_username,msg.sender,now);
        return 1;
	}

	// Iterating on requesrt array for a bank and filing allRequest array. Checking if any request are created by bank or there are no pending request by bank.
	// Initializing all request array using KYC_count of bank.
	function getBankRequests(address _bankAddress) view public isBankValid returns(KYCRequest[] memory){
	    require(banks[_bankAddress].KYC_count > 0,"NoRequestExistsForBank");
	    KYCRequest[] memory allRequests = new KYCRequest[](banks[_bankAddress].KYC_count);
	    uint index = 0;
	    for(uint i=0;i<requests.length;i++){
	        if(requests[i].BankAddress == _bankAddress){
	            allRequests[index] = requests[i];
	            index++;
	        }
	    }
	    require(index > 0,"NoPendingRequestsExist");
	    return allRequests;
	}


	// Using banksUpvoted mapping to store all banks upvoted for the bank using bankAddress as key.
	// checking if bank already upvoted using function modifier checkIfAlreadyUpvotedBank and bank cannot self vote.
	function upvoteBank(address _bankAddress) external isBankValid checkIfAlreadyUpvotedBank(_bankAddress) returns (uint){
	    require(_bankAddress != msg.sender,"CannotSelfVote");
        banksUpvoted[_bankAddress].push(msg.sender);
        banks[_bankAddress].Rating = (banksUpvoted[_bankAddress].length * 100) / noOfBanks ;
        emit UpvoteBankEvent(_bankAddress,msg.sender,now);
        return 1;
	}
	
	// Checking if address initializing the transaction is actually bank in function modifier isBankValid.
	// Checking if requested bank is added using require with reason message. 
	function getBankRating(address _bankAddress) view public isBankValid returns(uint){
	    require(banks[_bankAddress].regNumber != 0, "RequestedBankDoesNotExists");
	    return banks[_bankAddress].Rating;
	}
	

	function getCustomerRating(bytes32 _username) view public isBankValid returns(uint){
        require(customers[_username].CustomerData != 0, "CustomerDoesNotExists");
	    return customers[_username].Rating;
	}
	
	function getAccessHistory(bytes32 _username) view public isBankValid returns(address){
	    require(customers[_username].CustomerData != 0, "CustomerDoesNotExists");
	    return customers[_username].Bank;
	}
	
	function getBankDetails(address _bankAddress) view isBankValid public returns(Bank memory){
	    require(banks[_bankAddress].regNumber != 0, "RequestedBankDoesNotExists");
	    return banks[_bankAddress];
	}
	
	// modifier to check if bank already upvoted for customer.
	modifier checkIfAlreadyUpvoted(bytes32 _username) { 
        for(uint i=0;i< upvotes[_username].length;i++) {
            if(upvotes[_username][i] == msg.sender){
               require(false,"BankAlreadyUpvotedForCustomer");
            }
        }
        _;
	}
	
	// modifier to check if bank already upvoted for the bank.
	modifier checkIfAlreadyUpvotedBank(address _bankAddress) { 
        for(uint i=0;i< banksUpvoted[_bankAddress].length;i++) {
            if(banksUpvoted[_bankAddress][i] == msg.sender){
               require(false,"BankAlreadyUpvotedForBank");
            }
        }
        _;
	}

	// modifier to check if address initiating a transaction in added as bank.
	modifier isBankValid() { 
	    require(banks[msg.sender].regNumber != 0,"BankDoesNotExists");
		_;
	}
	
	// checking if requested customer is added as a customer in the system.
	modifier isCustomerValid(bytes32 Username) { 
	    require(customers[Username].CustomerData != 0,"CustomerDoesNotExists");
		_;
	}
	
	// checking while adding customer that is it allowed to process or no request exist for that username.
	modifier isCustomerAllowed(bytes32 Username) { 
		bool isCustomerAllowedRes = false;
		bool isCustomerPresent = false;
	    for(uint i=0;i<requests.length;i++){
	        if(requests[i].Username == Username ){
	            isCustomerPresent = true;
	            if(requests[i].IsAllowed){
	                isCustomerAllowedRes = requests[i].IsAllowed;
	                break;
	            }
	           
	        }
	    }
	    require(isCustomerPresent,"CustomerRequestNotCreated");
	    require(isCustomerAllowedRes,"CustomerNotAllowedToProcess");
		_;
	}
	
    /*modifier validateBankVerification(string memory Username,string memory CustomerData) { 
    	bool isRequestGeneratedRes = false;
    	bool isCustomerAllowedRes = false;
	    for(uint i=0;i<requests.length;i++){
	        if(keccak256(bytes(requests[i].Username)) == keccak256(bytes(Username))){
	            require(keccak256(bytes(requests[i].CustomerData)) == keccak256(bytes(CustomerData)),"VerificationNotSuccessful");
	            isRequestGeneratedRes = true;
	        }
	    }
	    require(isRequestGeneratedRes==true,"RequestNotCreatedForCustomer");
		_;
	}*/
	
} 
