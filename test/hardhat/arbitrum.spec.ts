import { setChain } from './utils'
import { prepareMarketTest } from './market/testHelper'
import * as helpers from '@nomicfoundation/hardhat-network-helpers'
import { pythSpec } from './oracle_provider/specs'
describe('[arbitrum]', async () => {
  let initChainSnapshot: helpers.SnapshotRestorer
  let deps: any
  const targetNetwork = 'arbitrum_goerli'
  before(async () => {
    console.log('set chain')
    await setChain(targetNetwork)
    deps = await prepareMarketTest('arbitrum')
    initChainSnapshot = await helpers.takeSnapshot()
  })

  beforeEach(async () => {
    await initChainSnapshot.restore()
  })
  const { feeSpec, lensSpec, liquidationSpec, liuqiditySpec, tradeSpec } = require('./market/specs')

  const getDeps = () => deps
  feeSpec(getDeps)
  lensSpec(getDeps)
  liquidationSpec(getDeps)
  liuqiditySpec(getDeps)
  tradeSpec(getDeps)
  pythSpec(targetNetwork)
})
