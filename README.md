# ZapMinionSummoner
Zap Minion and Factory

# Deployment
1. Deploy Molochv2 with WETH as an approved Currency
2. Copy paste code into Remix
3. Deploy ZapMinion (no inputs) to use as template
4. Deploy ZapMinion Summoner with template address as constructor address
5. Deploy some minions - will only work with Molochv2s with WETH as an approved currency. 

# Overview
This is a ZapMinion for generating membership proposals to a Moloch V2 with WETH as an approved currency. Users can generated their membership proposal by sending enough ETH directly to the ZapMinion address. 

The ZapMinion uses the simple EIP 1167 Proxy Pattern to minimize gas cost. 

## Zap Minion Config
Setup a ZapMinion for a WETH accepting Moloch by setting a Manager, a Moloch, a Join Rate, and Zap Details. 

* The Manager will have the power to update configuration variables--this manager can be another minion. 

* The Moloch is the moloch to which membership proposals are sent. 

* The Zap Rate is the number of ETH required for 1 share. Members should send in denominations of the Zap Rate, otherwise they should expect shares rounded down to the nearest Zap Rate (i.e. if the Zap rate is 2 ETH and they send 5 ETH, they will submit a proposal for 2 shares.)

* The Zap Details are the string details submitted with each membership proposal. 

Note: TODO is alter the zap rate to accept less than 1 ETH per share.

## Use 

Prospective members just need to send their ETH directly to the ZapMinion address. The ZapMinion uses a recieve function to deal with the submission of the membership proposal. The membership proposal will be submitted in WETH, with msg.value / Zap Rate / (10**18). The minimum contribution is 1 share per ETH.The details for the proposal will be whatever is in the Zap Details. 

* On xDAI rather than ETH it'll be xDAI to wxDAI. 

A Zap sender can still cancel their membership proposal, if it has not been sponsored in the Moloch, by calling cancelZapProposal with the proposalId that corresponds to their membership proposal. After the proposal is canceled they can recover their funds in WETH by calling drawZapProposal again with the correct proposalId. 

Finally, a ZapMinion's manager can update the ZapMinion's configs by calling updateZapMol. The settings that can be updated are: 

* the manager address
* the Zap Rate
* the Zap Details 
* the WETH address
* the Moloch address 

## Deployments

- xDAI (shares zap) - IN TESTING

- xDAI (loot zap) - IN TESTING

