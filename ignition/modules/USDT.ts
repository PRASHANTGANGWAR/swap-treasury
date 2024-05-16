import { buildModule } from "@nomicfoundation/hardhat-ignition/modules";

const USDTModule = buildModule("USDTModule", (m) => {

  const usdt = m.contract("USDT", []);

  return { usdt };
});

export default USDTModule;