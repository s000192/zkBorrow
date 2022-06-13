// eslint-disable-next-line node/no-unpublished-require
const { ethers } = require("hardhat");

module.exports = async function ({ getNamedAccounts, deployments }) {
  const { deploy } = deployments;

  const { deployer } = await getNamedAccounts();

  const zkUsd = await ethers.getContract("ZkUsd");
  const oracle = await ethers.getContract("MockOracle");
  await deploy("Vault", {
    from: deployer,
    args: [zkUsd.address, oracle.address],
    log: true,
    deterministicDeployment: false,
  });
};

module.exports.tags = ["Vault"];
