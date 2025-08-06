// scripts/collectionStats.ts
// old config + canon
import { ethers } from "hardhat";
import { HashCanonNFT } from "../typechain-types";

async function main() {
  const [owner] = await ethers.getSigners();

  // ─── deploy local test stack ───
  const Storage   = await ethers.getContractFactory("HashCanonSVGStorage");
  const storage   = await Storage.deploy();

  const Renderer  = await ethers.getContractFactory("FullMandalaRenderer");
  const renderer  = await Renderer.deploy(await storage.getAddress());

  const NFT       = await ethers.getContractFactory("HashCanonNFT");
  const nft = (await NFT.deploy(await renderer.getAddress())) as HashCanonNFT;

  await nft.connect(owner).enableMinting();

  const PRICE   = ethers.parseEther("0.002");
  const GENESIS = Number(await nft.GENESIS_SUPPLY());

  // ─── bulk-mint all 8192 tokens ───
  console.time("mint-all");
  const BATCH = 500;
  for (let i = 0; i < GENESIS; i++) {
    await nft.connect(owner).mint({ value: PRICE });
    if ((i + 1) % BATCH === 0) await ethers.provider.send("evm_mine");
  }
  console.timeEnd("mint-all");

  // ─── analyse metadata ───
  const total = Number(await nft.totalSupply());
  const evenBuckets: Record<string, number> = {};
  const passages:    Record<number, number> = {};

  for (let id = 1; id <= total; id++) {
    const uri  = await nft.tokenURI(id);
    const json = JSON.parse(Buffer.from(uri.split(",")[1], "base64").toString());

    const attr: Record<string, string> = Object.fromEntries(
      json.attributes.map((a: any) => [a.trait_type, a.value])
    );

    const even = attr.Evenness;               // "0.0" … "1.0"
    if (even === "1.0") perfectlyEven++;
    evenBuckets[even] = (evenBuckets[even] || 0) + 1;

    const p = Number(attr.Passages);
    passages[p] = (passages[p] || 0) + 1;
  }

  // ─── output ───
  console.log(\nTokens minted        : ${total});
  console.log("\nEvenness distribution:");
  Object.keys(evenBuckets)
    .sort((a, b) => parseFloat(a) - parseFloat(b))
    .forEach(k =>
      console.log(
          ${k.padEnd(4, " ")}: ${evenBuckets[k]} (${(
          (evenBuckets[k] / total) * 100
        ).toFixed(2)} %)
      )
    );

  console.log("\nPassages distribution:");
  Object.keys(passages)
    .map(Number)
    .sort((a, b) => a - b)
    .forEach(k =>
      console.log(
          ${k.toString().padStart(2, "0")} : ${passages[k]} (${(
          (passages[k] / total) * 100
        ).toFixed(2)} %)
      )
    );
}

main().catch(err => {
  console.error(err);
  process.exit(1);
});