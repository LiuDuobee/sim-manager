import Dexie, { type Table } from 'dexie'

export type CardType = 'Physical' | 'eSIM' | 'Programmable_eSIM'
export type LocationType = 'Device' | 'SmartCard' | 'Binder'
export type BillingCycle = 'Monthly' | 'Yearly' | 'PayGo'

export type SimCard = {
  id: string
  phoneNumber: string
  carrierName: string
  countryCode: string
  cardType: CardType
  themeColor: string
  locationType: LocationType
  hostName: string
  slotDetail: string
  isActive: boolean
  planName: string
  balance: number
  currency: 'CNY' | 'HKD' | 'GBP' | 'USD' | 'JPY'
  billingCycle: BillingCycle
  cycleCost: number
  cnyMonthlyEstimate: number
  keepAliveCycleDays: number
  keepAliveAction: string
  lastKeepAliveDate: string
  nextDeadlineDate: string
  iccid: string
  pin1: string
  puk1: string
  esimLpaCode: string
  boundServices: string[]
  notes: string
  keepAliveLog: string[]
}

class CardDatabase extends Dexie {
  cards!: Table<SimCard, string>
  constructor() {
    super('simvault-db')
    this.version(1).stores({ cards: 'id, countryCode, cardType, locationType, isActive' })
  }
}

export const cardDb = new CardDatabase()

const dateFromNow = (days: number) => {
  const date = new Date()
  date.setDate(date.getDate() + days)
  return date.toISOString()
}

export const seedCards: SimCard[] = [
  { id: 'cn-mobile', phoneNumber: '+86 138 0013 8000', carrierName: '中国移动', countryCode: 'CN', cardType: 'Physical', themeColor: 'ocean', locationType: 'Device', hostName: 'iPhone 主卡', slotDetail: 'Slot 1', isActive: true, planName: '8 元保号', balance: 42.8, currency: 'CNY', billingCycle: 'Monthly', cycleCost: 8, cnyMonthlyEstimate: 8, keepAliveCycleDays: 180, keepAliveAction: '发送 1 条短信', lastKeepAliveDate: dateFromNow(-154), nextDeadlineDate: dateFromNow(26), iccid: '898600F31023 0000 1234', pin1: '1234', puk1: '12345678', esimLpaCode: '', boundServices: ['Telegram', '银行卡'], notes: '家人副卡，低频使用', keepAliveLog: [] },
  { id: 'giffgaff', phoneNumber: '+44 7400 123456', carrierName: 'giffgaff', countryCode: 'GB', cardType: 'eSIM', themeColor: 'sunset', locationType: 'Device', hostName: 'iPhone 副卡', slotDetail: 'eSIM Profile #2', isActive: false, planName: 'Pay As You Go', balance: 15.2, currency: 'GBP', billingCycle: 'PayGo', cycleCost: 0, cnyMonthlyEstimate: 0, keepAliveCycleDays: 180, keepAliveAction: '流量变动或发送短信', lastKeepAliveDate: dateFromNow(-38), nextDeadlineDate: dateFromNow(142), iccid: '8944112345678901234', pin1: '0000', puk1: '87654321', esimLpaCode: 'LPA:1$prod.giffgaff.com$A1B2C3D4', boundServices: ['Google', 'Apple ID (UK)'], notes: '英国旅行卡', keepAliveLog: [] },
  { id: 'club-sim', phoneNumber: '+852 5123 8888', carrierName: 'Club SIM', countryCode: 'HK', cardType: 'Physical', themeColor: 'jade', locationType: 'Binder', hostName: '卡册 A 区', slotDetail: '第 2 页 · 第 4 格', isActive: false, planName: '年费保号', balance: 108, currency: 'HKD', billingCycle: 'Yearly', cycleCost: 38, cnyMonthlyEstimate: 3.2, keepAliveCycleDays: 365, keepAliveAction: '充值任意金额', lastKeepAliveDate: dateFromNow(-295), nextDeadlineDate: dateFromNow(70), iccid: '8985201234567890123', pin1: '8888', puk1: '11223344', esimLpaCode: '', boundServices: ['Telegram', '银行卡'], notes: '香港收藏卡，实体卡保存完好', keepAliveLog: [] },
  { id: 'tmobile', phoneNumber: '+1 213 555 0198', carrierName: 'T-Mobile', countryCode: 'US', cardType: 'Programmable_eSIM', themeColor: 'night', locationType: 'SmartCard', hostName: 'eSTK.me #1', slotDetail: 'Profile #3', isActive: true, planName: 'Connect 5GB', balance: 12, currency: 'USD', billingCycle: 'Monthly', cycleCost: 10, cnyMonthlyEstimate: 72, keepAliveCycleDays: 90, keepAliveAction: '流量变动', lastKeepAliveDate: dateFromNow(-78), nextDeadlineDate: dateFromNow(12), iccid: '8901260987654321012', pin1: '1111', puk1: '99887766', esimLpaCode: 'LPA:1$rsp.truphone.com$TMOBILE-DEMO', boundServices: ['Google', 'Apple ID (UK)'], notes: '写卡器测试槽位', keepAliveLog: [] },
  { id: 'rakuten', phoneNumber: '+81 70 1234 5678', carrierName: 'Rakuten', countryCode: 'JP', cardType: 'eSIM', themeColor: 'sakura', locationType: 'Binder', hostName: '卡册 B 区', slotDetail: '第 1 页 · 第 2 格', isActive: false, planName: 'Rakuten 最低月租', balance: 680, currency: 'JPY', billingCycle: 'Monthly', cycleCost: 980, cnyMonthlyEstimate: 45, keepAliveCycleDays: 180, keepAliveAction: '发送 1 条短信', lastKeepAliveDate: dateFromNow(-102), nextDeadlineDate: dateFromNow(78), iccid: '440101234567890', pin1: '2468', puk1: '12344321', esimLpaCode: 'LPA:1$service.rakuten.jp$JP-DEMO', boundServices: ['Google'], notes: '日本短期旅行使用', keepAliveLog: [] },
]
