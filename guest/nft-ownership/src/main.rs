use alloy_primitives::{Address, U256};
use alloy_sol_types::{sol, SolValue};
use risc0_op_steel::{
    optimism::{OpEvmInput, OP_SEPOLIA_CHAIN_SPEC},
    Commitment, Contract,
};
use risc0_zkvm::guest::env;

sol! {
    interface IERC721 {
        function ownerOf(uint256 tokenId) external view returns (address);
    }

    struct Journal {
        Commitment commitment;
        address tokenAddress;
        uint256 tokenId;
        address owner;
    }
}

fn main() {
    // Read the input from the guest environment
    let op_evm_input: OpEvmInput = env::read();
    let token_address: Address = env::read();
    let token_id: U256 = env::read();

    // Create the environment
    let env = op_evm_input.into_env(&OP_SEPOLIA_CHAIN_SPEC);

    // Execute the view call
    let call = IERC721::ownerOfCall { tokenId: token_id };
    let owner = Contract::new(token_address, &env)
        .call_builder(&call)
        .call();

    // Commit the journal
    let journal = Journal {
        commitment: env.into_commitment(),
        tokenAddress: token_address,
        tokenId: token_id,
        owner: owner,
    };
    env::commit_slice(&journal.abi_encode());
}
