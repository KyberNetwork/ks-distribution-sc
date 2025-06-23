use alloy::{
    primitives::{Address, U256},
    sol,
};
use anyhow::{bail, Context, Result};
use clap::Parser;
use guest::NFT_OWNERSHIP_ELF;
use risc0_ethereum_contracts::encode_seal;
use risc0_op_steel::{
    ethereum::{EthEvmEnv, ETH_SEPOLIA_CHAIN_SPEC},
    host::BlockNumberOrTag,
    optimism::{OpEvmEnv, OP_SEPOLIA_CHAIN_SPEC},
    Contract, DisputeGameIndex,
};
use risc0_zkvm::{default_prover, ExecutorEnv, ProverOpts, VerifierContext};
use tokio::task;
use url::Url;

sol! {
    interface IERC721 {
        function ownerOf(uint256 tokenId) external view returns (address);
    }

    interface IKSDistributorV2ZK {
        struct Commitment {
            uint256 id;
            bytes32 digest;
            bytes32 configID;
        }

        struct ERC721Info {
            uint256 chainId;
            address erc721Addr;
            uint256 erc721Id;
        }

        struct ZKProof {
            Commitment commitment;
            bytes seal;
        }

        function verifyERC721Ownership(ERC721Info calldata erc721Info, ZKProof calldata zkProof)
            external
            view
            returns (bool);
    }
}

#[derive(Parser, Debug)]
#[clap(author, version, about, long_about = None)]
struct Args {
    /// The URL of the L1 RPC endpoint
    #[clap(long, env)]
    l1_rpc_url: Url,
    /// The URL of the L2 RPC endpoint
    #[clap(long, env)]
    l2_rpc_url: Url,
    /// The address of the L2 portal proxy
    #[clap(long, env)]
    l2_portal_proxy: Address,
    /// The address of the verifier
    #[clap(long, env)]
    verifier: Address,
    /// The address of the distributor
    #[clap(long, env)]
    distributor: Address,
    /// The address of the ERC721 token
    #[clap(long, env)]
    token_address: Address,
    /// The ID of the ERC721 token
    #[clap(long, env)]
    token_id: U256,
    /// The segment limit in powers of 2
    #[clap(long, env)]
    segment_limit_po2: u32,
}

#[tokio::main]
async fn main() -> Result<()> {
    tracing_subscriber::fmt()
        .with_env_filter(tracing_subscriber::EnvFilter::from_default_env())
        .init();

    match dotenvy::dotenv() {
        Ok(path) => tracing::debug!("Loaded environment variables from {:?}", path),
        Err(e) if e.not_found() => tracing::debug!("No .env file found"),
        Err(e) => bail!("failed to load .env file: {}", e),
    }
    let args = Args::parse();

    // Build an environment based on the state of the latest finalized fault dispute game
    let builder = OpEvmEnv::builder()
        .dispute_game_from_rpc(args.l2_portal_proxy, args.l1_rpc_url.clone())
        .game_index(DisputeGameIndex::Finalized);
    let mut op_evm_env = builder
        .rpc(args.l2_rpc_url)
        .chain_spec(&OP_SEPOLIA_CHAIN_SPEC)
        .build()
        .await?;

    // Preflight the call
    let mut token_contract = Contract::preflight(args.token_address, &mut op_evm_env);
    let ownerof_call = IERC721::ownerOfCall {
        tokenId: args.token_id,
    };
    let owner = token_contract.call_builder(&ownerof_call).call().await?;
    tracing::info!(
        "Owner of token {} in ERC721 contract {}: {}",
        args.token_id,
        args.token_address,
        owner
    );

    let commitment = op_evm_env.commitment();
    let op_evm_input = op_evm_env.into_input().await?;
    let prove_info = task::spawn_blocking(move || {
        let env = ExecutorEnv::builder()
            .write(&op_evm_input)?
            .write(&args.token_address)?
            .write(&args.token_id)?
            .segment_limit_po2(args.segment_limit_po2)
            .build()
            .unwrap();

        default_prover().prove_with_ctx(
            env,
            &VerifierContext::default(),
            NFT_OWNERSHIP_ELF,
            &ProverOpts::groth16(),
        )
    })
    .await?
    .context("Failed to prove")?;
    tracing::debug!("Finished proving: {:?}", prove_info.stats);

    let erc721_info = IKSDistributorV2ZK::ERC721Info {
        chainId: U256::from(OP_SEPOLIA_CHAIN_SPEC.chain_id),
        erc721Addr: args.token_address,
        erc721Id: args.token_id,
    };
    let zk_proof = IKSDistributorV2ZK::ZKProof {
        commitment: IKSDistributorV2ZK::Commitment {
            id: commitment.id,
            digest: commitment.digest,
            configID: commitment.configID,
        },
        seal: encode_seal(&prove_info.receipt)
            .context("Failed to encode seal")?
            .into(),
    };

    let mut eth_evm_env = EthEvmEnv::builder()
        .rpc(args.l1_rpc_url)
        .block_number_or_tag(BlockNumberOrTag::Finalized)
        .chain_spec(&ETH_SEPOLIA_CHAIN_SPEC)
        .build()
        .await?;

    let mut distributor_contract = Contract::preflight(args.distributor, &mut eth_evm_env);
    let verify_call = IKSDistributorV2ZK::verifyERC721OwnershipCall {
        erc721Info: erc721_info,
        zkProof: zk_proof,
    };
    let mut verify_call_builder = distributor_contract.call_builder(&verify_call);
    verify_call_builder.tx.caller = owner;
    let result = verify_call_builder.call().await?;
    tracing::info!("Result: {:?}", result);

    Ok(())
}
