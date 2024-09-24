## Liquid NFT

**Liquid NFT is a marketplace protocol to provide fungible liquidity to non-fungible token (NFT) collections.**

# Introduction
This repository is experimental and in progress. DO NOT USE in production.


# Goals & Design
The main goal of the protocol is to grant access to instant floor liquidity across all kinds of rarities in a collection. Additionally, the price differentiation is achieved through liquid listing and auction listing after the remaining value is sold.

When a user deposits an NFT, fungible collection tokens (ERC-20) representing these NFTs are issued to the depositor which can be traded directly on decentralized exchanges (DEXs), such as Uniswap, or provide liquidity to AMM pools. Mid-tier and rare items are treated equally from the liquidity perspective.
