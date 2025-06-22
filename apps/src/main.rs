use alloy::{
    primitives::{Address, U256},
    signers::local::PrivateKeySigner,
    sol,
    sol_types::SolValue,
};
use anyhow::{bail, Context, Result};

sol! {
    struct ERC721Info {
        uint256 chainId;
        address erc721Addr;
        uint256 erc721Id;
    }

    struct RewardsInfo {
        address[] tokens;
        uint256[] amounts;
    }

    struct ZKProof {
        bytes seal;
        bytes commitment;
    }

    function claimRewardsForERC721(
        bytes32 campaignId,
        ERC721Info calldata erc721Info,
        ZKProof calldata zkProof,
        RewardsInfo calldata rewardsInfo,
        bytes32[] calldata proof,
        address recipient,
        address hook,
        bytes calldata hookData
    ) external;
}

#[tokio::main]
async fn main() -> Result<()> {
    Ok(())
}
