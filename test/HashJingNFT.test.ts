import { ethers, network } from "hardhat";
import { expect } from "chai";
import { HashJingNFT } from "../typechain-types";

describe("HashJingNFT – basic minting", function () {
  this.timeout(120_000);                    // ← 2 мин на весь suite
  let nft: HashJingNFT;
  const price = ethers.parseEther("0.002");

  /* ---------------- deploy fresh contracts ---------------- */
  beforeEach(async () => {
    const Storage  = await ethers.getContractFactory("HashJingSVGStorage");
    const storage  = await Storage.deploy();

    const Renderer = await ethers.getContractFactory("FullMandalaRenderer");
    const renderer = await Renderer.deploy(await storage.getAddress());

    const NFT      = await ethers.getContractFactory("HashJingNFT");
    nft            = await NFT.deploy(await renderer.getAddress());
  });

  it("mints one token and increases totalSupply", async () => {
    const [, alice] = await ethers.getSigners();
    await expect(nft.connect(alice).mint({ value: price }))
      .to.changeTokenBalance(nft, alice, +1);
    expect(await nft.totalSupply()).to.equal(1n);
  });

  /* ---- sequential 8 192 mints (авто-майн ВКЛ) ---- */
  it("reverts when max 8192 tokens minted", async () => {
    const [, minter] = await ethers.getSigners();
    for (let i = 0; i < 8192; i++) {
      await nft.connect(minter).mint({ value: price });
    }
    await expect(nft.connect(minter).mint({ value: price }))
      .to.be.revertedWithCustomError(nft, "SoldOut");
  });

  it("returns tokenURI with Balanced and Passages traits", async () => {
    const [, user] = await ethers.getSigners();
    await nft.connect(user).mint({ value: price });

    const uri  = await nft.tokenURI(1n);
    const json = JSON.parse(Buffer.from(uri.split(",")[1], "base64").toString());
    const traits = json.attributes.map((a: any) => a.trait_type);
    expect(traits).to.include.members(["Balanced", "Passages"]);
  });

  it("supports ERC165: ERC721, Metadata, ERC2981", async () => {
    const ids = ["0x80ac58cd", "0x5b5e139f", "0x2a55205a"];
    for (const iid of ids) expect(await nft.supportsInterface(iid)).to.be.true;
  });

  it("allows treasury to withdraw contract balance", async () => {
    const [owner, alice] = await ethers.getSigners();
    await nft.connect(alice).mint({ value: price });

    const balBefore = await ethers.provider.getBalance(owner.address);
    const tx        = await nft.connect(owner).withdraw();
    const receipt   = await tx.wait();
    const gasCost   = receipt.gasUsed * receipt.gasPrice!;
    const balAfter  = await ethers.provider.getBalance(owner.address);

    expect(balAfter - balBefore + gasCost).to.be.closeTo(price, 10n ** 14n);
  });

  it("reverts if non-treasury calls withdraw", async () => {
    const [, alice] = await ethers.getSigners();
    await expect(nft.connect(alice).withdraw())
      .to.be.revertedWithCustomError(nft, "NotTreasury");
  });
});
