const BankContract = artifacts.require("BankContract");

module.exports = function (deployer) {
  deployer.deploy(BankContract);
};
