module.exports = async function ({ getNamedAccounts, deployments }) {
  const { deploy } = deployments;

  const { deployer } = await getNamedAccounts();

  await deploy("ZkUsd", {
    from: deployer,
    args: ["Zero Knowledge USD", "ZkUSD"],
    log: true,
    deterministicDeployment: false,
  });
};

module.exports.tags = ["ZkUsd"];
