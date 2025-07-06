// scripts/collectionStats.ts
import { ethers } from "hardhat";
import { HashJingNFT } from "../typechain-types";

async function main() {
  const [owner] = await ethers.getSigners();

  const Storage = await ethers.getContractFactory("HashJingSVGStorage");
  const storage = await Storage.deploy();

  const Renderer = await ethers.getContractFactory("FullMandalaRenderer");
  const renderer = await Renderer.deploy(await storage.getAddress());

  const NFT = await ethers.getContractFactory("HashJingNFT");
  const nft = (await NFT.deploy(await renderer.getAddress())) as unknown as HashJingNFT;

  await nft.connect(owner).enableMinting();

  const PRICE = ethers.parseEther("0.002");
  const GENESIS = Number(await nft.GENESIS_SUPPLY());

  console.time("mint-all");

  // Mint in batches of 500 to avoid block gas limit
  const BATCH = 500;
  for (let i = 0; i < GENESIS; i++) {
    await nft.connect(owner).mint({ value: PRICE });
    if ((i + 1) % BATCH === 0) {
      await ethers.provider.send("evm_mine");
    }
  }

  console.timeEnd("mint-all");

  const total = Number(await nft.totalSupply());
  let balanced = 0;
  const passages: Record<number, number> = {};

  for (let id = 1; id <= total; id++) {
    const uri = await nft.tokenURI(id);
    const json = JSON.parse(Buffer.from(uri.split(",")[1], "base64").toString());

    const attr: Record<string, string> = Object.fromEntries(
      json.attributes.map((a: any) => [a.trait_type, a.value])
    );

    if (attr.Balanced === "true") balanced++;
    const p = Number(attr.Passages);
    passages[p] = (passages[p] || 0) + 1;
  }

  console.log(`\nTokens minted   : ${total}`);
  console.log(`Balanced = true : ${balanced} (${(balanced / total * 100).toFixed(2)} %)`);

  console.log("\nPassages distribution:");
  Object.keys(passages)
    .map(Number)
    .sort((a, b) => a - b)
    .forEach(k =>
      console.log(
        `  ${k.toString().padStart(2, "0")} : ${passages[k]} (${(
          (passages[k] / total) *
          100
        ).toFixed(2)} %)`
      )
    );
}

main().catch(err => {
  console.error(err);
  process.exit(1);
});
