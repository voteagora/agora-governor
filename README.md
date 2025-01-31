# 🏛 Agora Governor

[![CI][ci-badge]][ci-url]

Core and peripheral contracts for the Agora Governor.

## Contracts

```ml
├─ AgoraGovernor — "Core governor with integrated hook system"
├─ Middleware — "Connector between modules and governor with proposal types"
├─ modules
│  ├─ ApprovalVoting — "Approval voting module"
│  ├─ Optimistic — "Optimistic voting module"
```

## Installation

To install with [**Foundry**](https://github.com/foundry-rs/foundry):

```sh
forge install voteagora/agora-governor
```

To install with [**Hardhat**](https://github.com/nomiclabs/hardhat):

```sh
npm install agora-governor
```

## Acknowledgements

These contracts were inspired by or directly modified from many sources, primarily:

- [OpenZeppelin](https://github.com/OpenZeppelin/openzeppelin-contracts)

[ci-badge]: https://github.com/cairoeth/sandwich-resistant-hook/actions/workflows/test.yml/badge.svg
[ci-url]: https://github.com/cairoeth/sandwich-resistant-hook/actions/workflows/test.yml
