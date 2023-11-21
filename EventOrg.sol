// SPDX-License-Identifier: GPL-3.0
// Event contract - 
//    1. Define event along with the types of tickets to be sold based on ticket's availability and price
//        a. Only Event Manager will define the event and the types of tickets for an event along with their availability.
//    2. Ability to buy, transfer and refund tickets
//        a. Customers can buy tickets for multiple events and also types of tickets.
//        b. Except Event Manager, everybody else can buy, transfer and refund tickets.
//        c. Refund window closes 24 hours before the event.
//        d. Customers can also view the available tickets along with the tickets alloted to them.

import "@openzeppelin/contracts/utils/Strings.sol";

pragma solidity >=0.5.0 <0.9.0;

contract EventContract
{

    address eventManagerAddress;

    struct Event{
        address eventManager;
        string name;
        uint date;
        uint ticketsCount;
        uint ticketsRemaining;
        string[] ticketTypes;
        uint[] ticketTypesPrices;
        uint[] ticketTypesCount;
    }

    struct TestData {
        string name;
        uint eventDate;
        uint totalTickets;
        string[] ticketTypes;
        uint[] ticketTypesPrices;
        uint[] ticketTypesCount;
        uint eventID;
    }

    uint eventId = 0;
    mapping(uint=>Event) public events;
    mapping(address=>mapping(uint=>mapping(string=>uint))) tickets;
    enum CheckType { CreateEvent, BuyTicket, TransferTicket, RefundTicket }

    constructor()
    {
        eventManagerAddress = msg.sender;
    }

    function checkData(CheckType checkType, TestData memory testData) private view returns(bool){
        bool allow = false;
        if(checkType == CheckType.CreateEvent)
        {
            require(msg.sender == eventManagerAddress, "Only Event Manager permitted to create event");
            require(bytes(testData.name).length > 0, "Invalid event name provided");
            require(testData.eventDate > block.timestamp, "You cannot create event for past date");
            require(testData.totalTickets > 0, "Cannot create event with 0 tickets");
            uint totalTicketTypesCount = 0;
            for (uint i = 0; i < testData.ticketTypesCount.length; i++) 
            {
                totalTicketTypesCount += testData.ticketTypesCount[i];
            }
            require(totalTicketTypesCount == testData.totalTickets, "Tickets Count are not matching the Ticket Type Count");
            require(testData.ticketTypes.length == testData.ticketTypesPrices.length && testData.ticketTypesPrices.length == testData.ticketTypesCount.length, "Invalid ticket Type/Price/Count provided");
            allow = true;
        }
        else if(checkType == CheckType.BuyTicket)
        {
            require(msg.sender != eventManagerAddress, "Event Manager is restricted from buying tickets");
            require(testData.eventDate < block.timestamp, "Ticket booking window has been closed");
            allow = true;
        }
        else if(checkType == CheckType.TransferTicket)
        {
            require(msg.sender != eventManagerAddress, "Event Manager is restricted from transfering tickets");
            require(testData.eventDate < block.timestamp, "Ticket booking window has been closed");
            allow = true;
        }
        else if(checkType == CheckType.RefundTicket)
        {
            require(msg.sender != eventManagerAddress, "Event Manager is restricted from refunding tickets");
            require((testData.eventDate - 86400) > block.timestamp, "Refund window closed 24 earlier");
            allow = true;
        }
        return allow;
    }

    function createEvent(string memory name, uint eventDate, uint totalTickets, string[] memory ticketTypes, uint[] memory ticketTypesPrices, uint[] memory ticketTypesCount) external
    {
        TestData memory testDataInstance;
        testDataInstance.name = name;
        testDataInstance.eventDate = eventDate;
        testDataInstance.totalTickets = totalTickets;
        testDataInstance.ticketTypes = ticketTypes;
        testDataInstance.ticketTypesPrices = ticketTypesPrices;
        testDataInstance.ticketTypesCount = ticketTypesCount;

        require(checkData(CheckType.CreateEvent, testDataInstance), "You are not allowed to move ahead");
        events[eventId] = Event(msg.sender, name, eventDate, totalTickets, totalTickets, ticketTypes, ticketTypesPrices, ticketTypesCount);
        eventId++; 
    }


    function buyTickets(uint eventID, string memory ticketType, uint quantity) external payable 
    {
        TestData memory testDataInstance;
        testDataInstance.eventID = eventID;
        require(checkData(CheckType.BuyTicket, testDataInstance), "You are not allowed to move ahead");
        Event storage _event = events[eventID];
        bool ticketsAvailable = false;
        uint index=0;
        for(index = 0; index < _event.ticketTypes.length; index++)
        {
            if(keccak256(abi.encodePacked(ticketType)) == keccak256(abi.encodePacked(_event.ticketTypes[index])))
            {
                if(_event.ticketTypesCount[index] >= quantity)
                {
                    if(_event.ticketTypesPrices[index] * quantity == msg.value)
                    {
                        ticketsAvailable = true;
                        break;
                    }
                }
            }
        }
        require(ticketsAvailable == true, "Requested tickets exceed availability or insufficient funds");
        _event.ticketsRemaining -= quantity;
        _event.ticketTypesCount[index] -= quantity;
        tickets[msg.sender][eventID][_event.ticketTypes[index]] += quantity;
    }

    function transferTickets(uint eventID, string memory ticketType, uint quantity, address toAddress) external 
    {
        TestData memory testDataInstance;
        testDataInstance.eventID = eventID;
        require(checkData(CheckType.TransferTicket, testDataInstance), "You are not allowed to move ahead");
        require(tickets[msg.sender][eventID][ticketType] >= quantity, "Transfer request exceeds purchased ticket quantity");
        tickets[toAddress][eventID][ticketType] += quantity;
        tickets[msg.sender][eventID][ticketType] -= quantity;
    }

    function refundTickets(uint eventID, string memory ticketType, uint quantity) external
    {

        TestData memory testDataInstance;
        testDataInstance.eventID = eventID;
        testDataInstance.eventDate = events[eventID].date;
        require(checkData(CheckType.RefundTicket, testDataInstance), "You are not allowed to move ahead");
        require(tickets[msg.sender][eventID][ticketType] >= quantity, "Refund request exceeds purchased ticket quantity");
        Event storage _event = events[eventID];
        
        int256 index = -1; // What if ticket type never existed
        for(uint i = 0; i < _event.ticketTypes.length; i++)
        {
            if(keccak256(abi.encodePacked(_event.ticketTypes[i])) == keccak256(abi.encodePacked(ticketType)))
            {
                index = int256(i);
                break;
            }
        }

        require(index >= 0, "Ticket type does not exist");
        address payable refundAddress = payable(msg.sender);
        refundAddress.transfer(quantity * _event.ticketTypesPrices[uint(index)]);
        _event.ticketTypesCount[uint(index)] += quantity;
        _event.ticketsRemaining += quantity;
        tickets[msg.sender][eventID][ticketType] -= quantity;
    }

    function checkMyTickets(uint eventID, string memory ticketType) external view returns(uint)
    {
        return tickets[msg.sender][eventID][ticketType];
    }

    function checkTicketsAvail(uint eventID) external view returns(string memory)
    {
        string memory ticketTypes = "";
        for(uint i = 0; i < events[eventID].ticketTypesCount.length; i++)
        {
            ticketTypes = string(abi.encodePacked(ticketTypes, events[eventID].ticketTypes[i], ": ", Strings.toString(events[eventID].ticketTypesPrices[i]), " wei - ", Strings.toString(events[eventID].ticketTypesCount[i]), " tickets | "));
        }
        return ticketTypes;
    }
}
