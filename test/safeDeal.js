const {expect} = require("chai");
const {upgrades, ethers} = require("hardhat");

describe("Checks SafeDeal Contract", function () {
    let chainId = 31337;
    let deployer;
    let signer;
    let moderator;
    let randomUser;
    let SafeDealInterface;
    let SafeDealContract;
    let tokenContract;


    // preparing busd
    it("Preparing", async function () {
        deployer = (await ethers.getSigners())[0];
        signer = (await ethers.getSigners())[1];
        moderator = (await ethers.getSigners())[2];
        randomUser = (await ethers.getSigners())[3];

        const testTokenInterface = await ethers.getContractFactory("TestToken");
        tokenContract = await testTokenInterface.deploy();

        SafeDealInterface = await ethers.getContractFactory("SafeDeal");
        SafeDealContract = await SafeDealInterface.deploy(tokenContract.address);

        await tokenContract.approve(SafeDealContract.address, ethers.constants.MaxUint256);

        // moderators library checks in other test file
        await SafeDealContract.addModerator(moderator.address);
    });

    it("Checking signer", async function () {
        expect(await SafeDealContract.setSigner(signer.address),
            "Can't add signer")
            .to.emit(SafeDealInterface, "NewSigner")
            .withArgs(signer.address);

        expect((await SafeDealContract.functions.signer())[0],
            "Signer are not updated").to.equal(signer.address);
    })

    it("Checking Open Position", async function () {
        let id = 100;
        let referrer = ethers.constants.AddressZero;
        let seller = deployer.address;
        let amount = 100;
        const serviceFee = 10;
        const referrerFee = 1;


        let signature = await signInfo(
            chainId,
            SafeDealContract.address,
            id,
            seller,
            referrer,
            amount,
            serviceFee,
            referrerFee
        )

        id = 101;

        await expect(SafeDealContract.start(
            id,
            seller,
            referrer,
            amount,
            serviceFee,
            referrerFee,
            signature
        ), "Sign are not working properly").to.revertedWith("invalid sign");

        id = 100
        await expect(SafeDealContract.start(
            id,
            seller,
            referrer,
            amount,
            serviceFee,
            referrerFee,
            signature
        ), "Seller is buyer").to.revertedWith("Seller can't be buyer");

        seller = ethers.constants.AddressZero;
        signature = await signInfo(
            chainId,
            SafeDealContract.address,
            id,
            seller,
            referrer,
            amount,
            serviceFee,
            referrerFee
        )
        await expect(SafeDealContract.start(
            id,
            seller,
            referrer,
            amount,
            serviceFee,
            referrerFee,
            signature
        ), "Seller is zero").to.revertedWith("Seller can't be zero");

        seller = "0xB7a5c3f3e1243f995f4B0B29de315B79d583194b";
        amount = 0;
        signature = await signInfo(
            chainId,
            SafeDealContract.address,
            id,
            seller,
            referrer,
            amount,
            serviceFee,
            referrerFee
        )

        await expect(SafeDealContract.start(
            id,
            seller,
            referrer,
            amount,
            serviceFee,
            referrerFee,
            signature
        ), "Amount is zero").to.revertedWith("Amount can't be zero");

        amount = 100;
        signature = await signInfo(
            chainId,
            SafeDealContract.address,
            id,
            seller,
            referrer,
            amount,
            serviceFee,
            referrerFee
        )

        await expect(SafeDealContract.start(
            id,
            seller,
            referrer,
            amount,
            serviceFee,
            referrerFee,
            signature
        ), "Referrer is zero").to.revertedWith("referrer can't be zero");
    })

    it("Open And close deal by buyer", async function () {
        const id = 1;
        const seller = "0xB7a5c3f3e1243f995f4B0B29de315B79d583194b";
        const referrer = "0x715B577Bb586e306c5cD9c98c948d37A712B3c82";
        const amount = 100;
        const serviceFee = 10;
        const referrerFee = 1;


        const signature = await signInfo(
            chainId,
            SafeDealContract.address,
            id,
            seller,
            referrer,
            amount,
            serviceFee,
            referrerFee
        )

        const balanceBefore = await tokenContract.balanceOf(deployer.address);

        let startTx = await SafeDealContract.start(
            id,
            seller,
            referrer,
            amount,
            serviceFee,
            referrerFee,
            signature
        );

        await checkEvent(startTx, "Started");

        const balanceAfter = await tokenContract.balanceOf(deployer.address);
        expect(
            balanceBefore
                .sub(amount.toString())
                .sub(serviceFee.toString())
                .sub(referrerFee.toString())
            , "Balance not changed").to.equal(balanceAfter);

        await expect(SafeDealContract.start(
            id,
            seller,
            referrer,
            amount,
            serviceFee,
            referrerFee,
            signature
        ), "Start started twice").to.be.reverted;

        const balanceSellerBefore = await tokenContract.balanceOf(seller);
        const balanceReferrerBefore = await tokenContract.balanceOf(referrer);
        const balanceOfContractBefore = await tokenContract.balanceOf(SafeDealContract.address);

        await expect(SafeDealContract.connect(randomUser).completeByBuyer(id),
            "Transaction called by not buyer"
        ).to.be.reverted;

        let closeTx = await SafeDealContract.completeByBuyer(id);
        await checkEvent(closeTx, "Completed");

        const balanceSellerAfter = await tokenContract.balanceOf(seller);
        const balanceReferrerAfter = await tokenContract.balanceOf(referrer);
        const balanceOfContractAfter = await tokenContract.balanceOf(SafeDealContract.address);


        expect(
            balanceSellerBefore.add(amount),
            "Seller balance are not updated")
            .to.equal(balanceSellerAfter);

        expect(balanceReferrerBefore.add(referrerFee),
            "Referrer balance are not updated")
            .to.equal(balanceReferrerAfter);

        expect(
            balanceOfContractAfter,
            "Service fee are not collected")
            .to.equal(balanceOfContractBefore.sub(amount).sub(referrerFee));

        expect(
            await SafeDealContract.getBalance(), "Balance are not updated"
        ).to.equal(serviceFee);
    })


    it("Open And close deal by moderator", async function () {
        const id = 1000;
        const seller = "0xB7a5c3f3e1243f995f4B0B29de315B79d583194b";
        const referrer = "0x715B577Bb586e306c5cD9c98c948d37A712B3c82";
        const amount = 100;
        const serviceFee = 10;
        const referrerFee = 1;


        const signature = await signInfo(
            chainId,
            SafeDealContract.address,
            id,
            seller,
            referrer,
            amount,
            serviceFee,
            referrerFee
        )

        await SafeDealContract.start(
            id,
            seller,
            referrer,
            amount,
            serviceFee,
            referrerFee,
            signature
        );

        const balanceSellerBefore = await tokenContract.balanceOf(seller);
        const balanceReferrerBefore = await tokenContract.balanceOf(referrer);
        const balanceOfContractBefore = await tokenContract.balanceOf(SafeDealContract.address);

        await expect(SafeDealContract.connect(randomUser).completeByModerator(id),
            "Transaction called by not moderator"
        ).to.be.reverted;

        let closeTx = await SafeDealContract.connect(moderator).completeByModerator(id);
        await checkEvent(closeTx, "Completed");

        const balanceSellerAfter = await tokenContract.balanceOf(seller);
        const balanceReferrerAfter = await tokenContract.balanceOf(referrer);
        const balanceOfContractAfter = await tokenContract.balanceOf(SafeDealContract.address);


        expect(
            balanceSellerBefore.add(amount),
            "Seller balance are not updated")
            .to.equal(balanceSellerAfter);

        expect(balanceReferrerBefore.add(referrerFee),
            "Referrer balance are not updated")
            .to.equal(balanceReferrerAfter);

        expect(
            balanceOfContractAfter,
            "Service fee are not collected")
            .to.equal(balanceOfContractBefore.sub(amount).sub(referrerFee));
    })

    it("Open And revert deal by moderator", async function () {
        const id = 1001;
        const seller = "0xB7a5c3f3e1243f995f4B0B29de315B79d583194b";
        const referrer = "0x715B577Bb586e306c5cD9c98c948d37A712B3c82";
        const amount = 100;
        const serviceFee = 10;
        const referrerFee = 1;


        const signature = await signInfo(
            chainId,
            SafeDealContract.address,
            id,
            seller,
            referrer,
            amount,
            serviceFee,
            referrerFee
        )

        await SafeDealContract.start(
            id,
            seller,
            referrer,
            amount,
            serviceFee,
            referrerFee,
            signature
        );


        const balanceBuyerBefore = await tokenContract.balanceOf(deployer.address);
        const balanceReferrerBefore = await tokenContract.balanceOf(referrer);
        const balanceOfContractBefore = await tokenContract.balanceOf(SafeDealContract.address);


        await expect(SafeDealContract.connect(randomUser).cancelByModerator(id),
            "Transaction called by not moderator"
        ).to.be.reverted;

        let closeTx = await SafeDealContract.connect(moderator).cancelByModerator(id);
        await checkEvent(closeTx, "Cancelled");

        const balanceBuyerAfter = await tokenContract.balanceOf(deployer.address);
        const balanceReferrerAfter = await tokenContract.balanceOf(referrer);
        const balanceOfContractAfter = await tokenContract.balanceOf(SafeDealContract.address);


        expect(
            balanceBuyerBefore.add(amount).add(referrerFee).add(serviceFee),
            "Seller balance are not updated")
            .to.equal(balanceBuyerAfter);

        expect(balanceReferrerBefore,
            "Referrer balance are not updated")
            .to.equal(balanceReferrerAfter);

        expect(
            balanceOfContractAfter,
            "Service fee are not collected")
            .to.equal(balanceOfContractBefore.sub(amount).sub(referrerFee).sub(serviceFee));
    })


    it("Checks withdraw function", async function () {
        const balanceBefore = await tokenContract.balanceOf(SafeDealContract.address);
        const balanceByContract = await SafeDealContract.getBalance();

        await expect(
            SafeDealContract.connect(randomUser).withdraw(deployer.address, balanceByContract),
            "Money was withdrawn not by the owner"
        ).to.be.reverted;

        await expect(
            SafeDealContract.connect(deployer).withdraw(ethers.constants.AddressZero, balanceByContract),
            "Money was withdrawn to zero address"
        ).to.be.revertedWith("Can't be zero address");

        await expect(
            SafeDealContract.connect(deployer).withdraw(deployer.address, balanceByContract.add("1")),
            "Money was withdrawn more than contract allow"
        ).to.be.revertedWith("insufficient tokens");

        let withdrawTx = await SafeDealContract.withdraw(randomUser.address,balanceByContract);

        await checkEvent(withdrawTx, "Withdraw");

        const balanceAfter = await tokenContract.balanceOf(SafeDealContract.address);

        expect(balanceBefore.sub(balanceByContract),"Money wasn't transfered").to.equal(balanceAfter);

        expect(await SafeDealContract.getBalance(),"Total Balance inside contract are not updating").to.equal("0");
    })

    async function signInfo(
        chainId,
        verifyingContract,
        id,
        seller,
        referrer,
        amount,
        serviceFee,
        referrerFee) {

        let domain = {
            name: "SafeDeal",
            version: "1.0",
            chainId,
            verifyingContract,
        }


        const dataType = {
            SafeDeal: [
                {name: "id", type: "uint256"},
                {name: "seller", type: "address"},
                {name: "referrer", type: "address"},
                {name: "amount", type: "uint256"},
                {name: "serviceFee", type: "uint256"},
                {name: "referrerFee", type: "uint256"},
            ],
        };

        let data = {
            id,
            seller,
            referrer,
            amount,
            serviceFee,
            referrerFee
        }

        return await signer._signTypedData(domain, dataType, data);

    }

    async function checkEvent(tx, eventName) {
        let receipt = await tx.wait();
        let events = receipt.events?.filter((x) => {
            return x.event === eventName
        })
        expect(events.length, "Event are not emmited").to.equal(1);
    }
});
