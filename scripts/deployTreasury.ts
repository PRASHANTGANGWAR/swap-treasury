// scripts/create-box.js
import { ethers, upgrades } from "hardhat";

async function main() {
    const Treasury = await ethers.getContractFactory("Treasury");
    const treasury = await upgrades.deployProxy(Treasury, [
        "0x3b22aF7D779f9F717D00380f3dCa2100bAf85EA5",
        "0x52f64B42Ce258dC85bF8A7426f65dCA6978544C6",
        "0xC33d30353A66708cD2020ef1633797BD42724741",
        1,
        "0xC33d30353A66708cD2020ef1633797BD42724741"
    ]);
    await treasury.waitForDeployment();
    console.log("Box deployed to:", await treasury.getAddress());
}

main();