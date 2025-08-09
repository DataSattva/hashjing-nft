// scripts/debugSingle.ts
import { ethers } from "hardhat";
import { HashCanonNFT } from "../typechain-types";

async function main() {
  /* 1. Deploy Storage → Renderer → NFT ------------------------------------ */
  const Storage  = await ethers.getContractFactory("HashCanonSVGStorage");
  const storage  = await Storage.deploy();

  const Renderer = await ethers.getContractFactory("FullMandalaRenderer");
  const renderer = await Renderer.deploy(await storage.getAddress());

  const NFT      = await ethers.getContractFactory("HashCanonNFT");
  const nft      = (await NFT.deploy(await renderer.getAddress())) as HashCanonNFT;

  /* 2. Enable minting and mint one token ---------------------------------- */
  await nft.enableMinting();
  await nft.mint({ value: ethers.parseEther("0.002") });

  /* 3. Read tokenURI(1) --------------------------------------------------- */
  const uri      = await nft.tokenURI(1);
  const jsonStr  = Buffer.from(uri.slice(29), "base64").toString("utf8");
  console.log("RAW JSON (first 200 chars):", jsonStr.slice(0, 200), "...");

  /* 4. Parse JSON and inspect attributes ---------------------------------- */
  const meta = JSON.parse(jsonStr);
  console.log("Attributes array:", meta.attributes);

  // ─── analyse metadata ───
  for (let id = 1; id <= total; id++) {
    try {
      const uri  = await nft.tokenURI(id);           // ← может ревертить
      const json = JSON.parse(Buffer.from(uri.slice(29), "base64").toString());

      const attr: Record<string, string> = Object.fromEntries(
        json.attributes.map((a: any) => [a.trait_type, a.value])
      );

      // … Evenness & Passages статистика (как было) …
    } catch (e: any) {
      console.error(`Token #${id} reverted:`, e.reason ?? e.message ?? e);
      break;                                         // останавливаемся на первом
    }
  }

}

main().catch(console.error);
