const {expect} = require("chai");
// const  = require("@nomicfoundation/hardhat-chai-matchers")
const {upgrades, ethers} = require("hardhat");


describe("Checks Moderators lib", function () {
    let deployer;
    let moderator1;
    let moderator2;
    let ModeratorsInterface;
    let ModeratorsContract;

    it("Preparing", async function () {
        deployer = (await ethers.getSigners())[0];
        moderator1 = (await ethers.getSigners())[1].address;
        moderator2 = (await ethers.getSigners())[2].address;

        ModeratorsInterface = await ethers.getContractFactory("Moderators");
        ModeratorsContract = await ModeratorsInterface.deploy();

        expect(await ModeratorsContract.totalModerators(), "Total are not zero")
            .to.equal(0);
    });

    it("Adding new moderators", async function () {
        expect(await ModeratorsContract.addModerator(moderator1),
            "Can't add moderator");

        expect(await ModeratorsContract.totalModerators(),
            "Total moderators are not updated")
            .to.equal("1");

        expect(await ModeratorsContract.moderators(moderator1),
            "Moderator didn't registered").to.true;

        await expect(ModeratorsContract.addModerator(moderator1),
            "Added same moderator").to
            .revertedWith("moderator already exists");

        await expect(ModeratorsContract.addModerator(ethers.constants.AddressZero)
            , "Added zero address moderator").to.be.reverted;


        let tx = await ModeratorsContract.addModerator(moderator2);
        await checkEvent(tx,"ModeratorAdded");

        expect(await ModeratorsContract.totalModerators(),
            "Total moderators are not updated")
            .to.equal("2");
    });

    it("Removing moderators", async function () {
        expect(await ModeratorsContract.removeModerator(moderator1),
            "Can't remove moderator");

        expect(await ModeratorsContract.totalModerators(),
            "Total moderators are not updated")
            .to.equal("1");

        expect(await ModeratorsContract.moderators(moderator1),
            "Moderator didn't registered").to.false;

        await expect(ModeratorsContract.removeModerator(moderator1),
            "Removed same moderator").to
            .revertedWith("moderator not found");

        await expect(ModeratorsContract.removeModerator(ethers.constants.AddressZero)
            , "Removed zero address moderator").to.be.reverted;

        let tx = await ModeratorsContract.removeModerator(moderator2);
        await checkEvent(tx,"ModeratorRemoved");

        expect(await ModeratorsContract.totalModerators(),
            "Total moderators are not updated")
            .to.equal("0");
    });

    async function checkEvent(tx, eventName) {
        let receipt = await tx.wait();
        let events = receipt.events?.filter((x) => {
            return x.event === eventName
        })
        expect(events.length, "Event are not emmited").to.equal(1);
    }
});