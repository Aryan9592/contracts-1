import { SignerWithAddress } from '@nomiclabs/hardhat-ethers/signers'
import { BigNumber, ethers } from 'ethers'
import { parseEther, parseUnits } from 'ethers/lib/utils'
import {
  IAccount,
  IAccountFactory,
  IAccountFactory__factory,
  IAccount__factory,
  IERC20Metadata,
  IERC20Metadata__factory,
  IOracleProvider,
  IOracleProvider__factory,
  ISwapRouter,
  ISwapRouter__factory,
  IUSUMMarket,
  IUSUMMarketFactory,
  IUSUMMarketFactory__factory,
  IUSUMMarket__factory,
  IUSUMRouter,
  IUSUMRouter__factory,
  IWETH9,
  IWETH9__factory
} from '../typechain-types'
import { PositionStructOutput } from './../typechain-types/contracts/core/interfaces/IUSUMMarket'

const QTY_DECIMALS = 4
const LEVERAGE_DECIMALS = 2
const FEE_RATE_DECIMALS = 4

export class ReplWallet {
  public readonly address: string
  public Account: IAccount

  static async create(
    signer: SignerWithAddress,
    addresses: {
      weth: string
      usdc: string
      swapRouter: string
      marketFactory: string
      oracleProvider: string
      accountFactory: string
      router: string
    },
    ensureAccount: boolean
  ): Promise<ReplWallet> {
    const weth = IWETH9__factory.connect(addresses.weth, signer)
    const usdc = IERC20Metadata__factory.connect(addresses.usdc, signer)
    const swapRouter = ISwapRouter__factory.connect(addresses.swapRouter, signer)
    const oracleProvider = IOracleProvider__factory.connect(addresses.oracleProvider, signer)
    const marketFactory = IUSUMMarketFactory__factory.connect(addresses.marketFactory, signer)
    const accountFactory = IAccountFactory__factory.connect(addresses.accountFactory, signer)
    const router = IUSUMRouter__factory.connect(addresses.router, signer)

    const marketAddress = await marketFactory.getMarkets()

    const market = IUSUMMarket__factory.connect(marketAddress[0], signer)

    const w = new ReplWallet(
      signer,
      weth,
      usdc,
      swapRouter,
      oracleProvider,
      marketFactory,
      market,
      router,
      accountFactory
    )

    if (ensureAccount) {
      await w.createAccount()
    }

    return w
  }

  private constructor(
    public readonly signer: SignerWithAddress,
    public readonly WETH9: IWETH9,
    public readonly USDC: IERC20Metadata,
    public readonly SwapRouter: ISwapRouter,
    public readonly OracleProvider: IOracleProvider,
    public readonly USUMMarketFactory: IUSUMMarketFactory,
    public readonly USUMMarket: IUSUMMarket,
    public readonly USUMRouter: IUSUMRouter,
    public readonly AccountFactory: IAccountFactory
  ) {
    this.address = signer.address
  }

  async createAccount() {
    let accountAddress = await this.AccountFactory['getAccount()']()
    if (accountAddress === ethers.constants.AddressZero) {
      await this.AccountFactory.createAccount()
      accountAddress = await this.AccountFactory['getAccount()']()
    }
    console.log(`create Account, signer: ${accountAddress}, ${this.signer.address}`)
    this.Account = IAccount__factory.connect(accountAddress, this.signer)
  }

  async wrapEth(eth: number) {
    await this.WETH9.deposit({ value: parseEther(eth.toString()) })
  }

  async swapEth(eth: number) {
    await this.WETH9.approve(this.SwapRouter.address, ethers.constants.MaxUint256)

    await this.SwapRouter.exactInputSingle({
      tokenIn: this.WETH9.address,
      tokenOut: this.USDC.address,
      // fee: 10000,
      fee: 3000,
      // fee: 500,
      recipient: this.address,
      deadline: Math.ceil(Date.now() / 1000) + 30,
      amountIn: parseEther(eth.toString()),
      amountOutMinimum: 0,
      sqrtPriceLimitX96: 0
    })

    await this.WETH9.approve(this.SwapRouter.address, 0)
  }

  async positions(): Promise<PositionStructOutput[]> {
    const positionIds = await this.Account.getPositionIds(this.USUMMarket.address)
    return await this.USUMMarket.getPositions(positionIds)
  }

  async openPosition(qty: number, leverage: number, takerMargin: number, makerMargin: number) {
    const decimals = await this.USDC.decimals()
    const _takerMargin = parseUnits(takerMargin.toString(), decimals)
    const _makerMargin = parseUnits(makerMargin.toString(), decimals)

    await this.USUMRouter.openPosition(
      this.USUMMarket.address,
      parseUnits(qty.toString(), QTY_DECIMALS),
      parseUnits(leverage.toString(), LEVERAGE_DECIMALS),
      _takerMargin,
      _makerMargin,
      _makerMargin // no limit trading fee
    )
  }

  async closePosition(positionId: number) {
    await this.USUMRouter.closePosition(this.USUMMarket.address, BigNumber.from(positionId))
  }

  async addLiquidity(feeRate: number, amount: number) {
    const decimals = await this.USDC.decimals()
    await this.USUMRouter.addLiquidity(
      this.USUMMarket.address,
      parseUnits(feeRate.toString(), FEE_RATE_DECIMALS),
      parseUnits(amount.toString(), decimals),
      this.address
    )
  }

  async claimLiquidity(receiptId: number) {
    await this.USUMRouter.claimLiquidity(this.USUMMarket.address, receiptId)
  }

  async removeLiquidity(feeRate: number, lpTokenAmount: number) {
    const decimals = await this.USDC.decimals()
    await this.USUMRouter.removeLiquidity(
      this.USUMMarket.address,
      parseUnits(feeRate.toString(), FEE_RATE_DECIMALS),
      parseUnits(lpTokenAmount.toString(), decimals),
      this.address
    )
  }

  async withdrawLiquidity(receiptId: number) {
    await this.USUMRouter.withdrawLiquidity(this.USUMMarket.address, receiptId)
  }
}
