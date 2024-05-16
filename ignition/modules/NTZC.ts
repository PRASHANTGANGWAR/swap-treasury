import { buildModule } from "@nomicfoundation/hardhat-ignition/modules";

const NTZCModule = buildModule("NTZCModule", (m) => {

  const ntzc = m.contract("NTZC", []);

  return { ntzc };
});

export default NTZCModule;