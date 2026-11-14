import { useEffect, useMemo, useState } from 'react'
import { AnimatePresence, motion } from 'framer-motion'
import {
  Archive,
  ArrowDownToLine,
  ArrowUpFromLine,
  CalendarDays,
  Check,
  ChevronDown,
  CircleHelp,
  Copy,
  CreditCard,
  Eye,
  EyeOff,
  Filter,
  Globe2,
  LayoutGrid,
  List,
  MapPin,
  Plus,
  Radio,
  Search,
  Settings2,
  ShieldCheck,
  Sparkles,
  Tag,
  Trash2,
  WalletCards,
  X,
  Zap,
} from 'lucide-react'
import { cardDb, seedCards, type SimCard } from './db'
import './index.css'

const money = new Intl.NumberFormat('zh-CN', { style: 'currency', currency: 'CNY', maximumFractionDigits: 0 })
const dateLabel = new Intl.DateTimeFormat('zh-CN', { month: 'short', day: 'numeric' })

const countryFlags: Record<string, string> = { CN: '🇨🇳', GB: '🇬🇧', HK: '🇭🇰', US: '🇺🇸', JP: '🇯🇵' }
const tagIcons: Record<string, string> = { Telegram: '✈️', 'Google': 'G', 'Apple ID (UK)': '', 银行卡: '▣' }

function daysUntil(date: string) {
  return Math.ceil((new Date(date).getTime() - Date.now()) / 86400000)
}

function statusFor(card: SimCard) {
  const days = daysUntil(card.nextDeadlineDate)
  if (days < 0) return { label: '已过期', color: 'danger', bar: 100 }
  if (days < 15) return { label: `${days} 天后死线`, color: 'danger', bar: Math.max(12, days / 15 * 100) }
  if (days < 60) return { label: `${days} 天后死线`, color: 'warning', bar: days / 60 * 100 }
  return { label: `${days} 天后死线`, color: 'safe', bar: Math.min(100, days / Math.max(card.keepAliveCycleDays, 180) * 100) }
}

function copyText(value: string) {
  navigator.clipboard?.writeText(value)
}

function exportIcs(card: SimCard) {
  const date = new Date(card.nextDeadlineDate)
  date.setDate(date.getDate() - 7)
  const day = date.toISOString().slice(0, 10).replaceAll('-', '')
  const end = new Date(date.getTime() + 3600000).toISOString().replaceAll('-', '').replaceAll(':', '').split('.')[0] + 'Z'
  const start = date.toISOString().replaceAll('-', '').replaceAll(':', '').split('.')[0] + 'Z'
  const ics = [
    'BEGIN:VCALENDAR',
    'VERSION:2.0',
    'PRODID:-//SIMVault//Keep Alive//CN',
    'BEGIN:VEVENT',
    `UID:${card.id}@simvault`,
    `DTSTAMP:${start}`,
    `DTSTART:${day}T090000`,
    `DTEND:${end}`,
    `SUMMARY:SIMVault 保号提醒 · ${card.carrierName}`,
    `DESCRIPTION:${card.keepAliveAction}`,
    'END:VEVENT',
    'END:VCALENDAR',
  ].join('\r\n')
  const link = document.createElement('a')
  link.href = URL.createObjectURL(new Blob([ics], { type: 'text/calendar' }))
  link.download = `${card.carrierName}-keep-alive.ics`
  link.click()
  URL.revokeObjectURL(link.href)
}

function App() {
  const [cards, setCards] = useState<SimCard[]>([])
  const [query, setQuery] = useState('')
  const [view, setView] = useState<'gallery' | 'table'>('gallery')
  const [country, setCountry] = useState('all')
  const [urgency, setUrgency] = useState('all')
  const [showForm, setShowForm] = useState(false)
  const [editing, setEditing] = useState<SimCard | null>(null)
  const [notice, setNotice] = useState('')

  useEffect(() => {
    cardDb.cards.toArray().then(async (stored) => {
      if (stored.length === 0) {
        await cardDb.cards.bulkAdd(seedCards)
        setCards(seedCards)
      } else setCards(stored)
    })
  }, [])

  const persist = async (next: SimCard[]) => {
    setCards(next)
    await cardDb.cards.clear()
    await cardDb.cards.bulkAdd(next)
  }

  const filtered = useMemo(() => cards.filter((card) => {
    const text = `${card.carrierName} ${card.phoneNumber} ${card.planName} ${card.hostName} ${card.boundServices.join(' ')}`.toLowerCase()
    const matchesText = text.includes(query.toLowerCase())
    const matchesCountry = country === 'all' || card.countryCode === country
    const days = daysUntil(card.nextDeadlineDate)
    const matchesUrgency = urgency === 'all' || (urgency === 'danger' && days < 15) || (urgency === 'warning' && days >= 15 && days < 60) || (urgency === 'safe' && days >= 60)
    return matchesText && matchesCountry && matchesUrgency
  }), [cards, country, query, urgency])

  const checkIn = async (card: SimCard) => {
    const now = new Date()
    const next = new Date(now)
    next.setDate(next.getDate() + card.keepAliveCycleDays)
    const updated = { ...card, lastKeepAliveDate: now.toISOString(), nextDeadlineDate: next.toISOString(), keepAliveLog: [...card.keepAliveLog, now.toISOString()] }
    await persist(cards.map((item) => item.id === card.id ? updated : item))
    setNotice(`${card.carrierName} 已完成保号打卡`)
    setTimeout(() => setNotice(''), 2600)
  }

  const removeCard = async (id: string) => {
    await persist(cards.filter((card) => card.id !== id))
  }

  const importJson = async (file: File) => {
    try {
      const imported = JSON.parse(await file.text()) as SimCard[]
      if (!Array.isArray(imported)) throw new Error('invalid')
      await persist(imported)
      setNotice(`已导入 ${imported.length} 张卡片`)
    } catch {
      setNotice('导入失败：JSON 文件格式不正确')
    }
    setTimeout(() => setNotice(''), 2600)
  }

  const exportJson = () => {
    const link = document.createElement('a')
    link.href = URL.createObjectURL(new Blob([JSON.stringify(cards, null, 2)], { type: 'application/json' }))
    link.download = 'simvault-backup.json'
    link.click()
    URL.revokeObjectURL(link.href)
  }

  const countries = [...new Set(cards.map((card) => card.countryCode))]
  const dangerCount = cards.filter((card) => daysUntil(card.nextDeadlineDate) < 30).length
  const physicalCount = cards.filter((card) => card.cardType === 'Physical').length
  const costPerMonth = cards.reduce((sum, card) => sum + (card.currency === 'CNY' ? card.cycleCost / (card.billingCycle === 'Yearly' ? 12 : 1) : card.cnyMonthlyEstimate), 0)

  return (
    <div className="app-shell">
      <header className="topbar">
        <div className="brand">
          <div className="brand-mark"><Sparkles size={18} /></div>
          <div><strong>SIMVault</strong><span>全球集卡者的本地数字卡册</span></div>
        </div>
        <div className="top-actions">
          <label className="import-button"><ArrowDownToLine size={16} /> 导入备份<input type="file" accept=".json" onChange={(event) => event.target.files?.[0] && importJson(event.target.files[0])} /></label>
          <button className="ghost-button" onClick={exportJson}><ArrowUpFromLine size={16} /> 导出 JSON</button>
          <button className="icon-button"><Settings2 size={18} /></button>
          <div className="avatar">SC</div>
        </div>
      </header>

      <main className="content">
        <section className="hero-row">
          <div>
            <p className="eyebrow"><Radio size={14} /> LOCAL-FIRST · OFFLINE READY</p>
            <h1>你的全球 SIM 收藏，<em>尽在掌握。</em></h1>
            <p className="hero-copy">记录每一张卡的故事、位置和保号节奏。数据只保存在你的设备里。</p>
          </div>
          <button className="primary-button" onClick={() => { setEditing(null); setShowForm(true) }}><Plus size={18} /> 收入新卡</button>
        </section>

        <section className="stats-grid">
          <StatCard icon={<WalletCards size={20} />} label="总藏卡数" value={String(cards.length).padStart(2, '0')} detail={`${physicalCount} 实体 · ${cards.length - physicalCount} eSIM`} accent="blue">
            <div className="mini-bars">{countries.map((item) => <span key={item} title={item} style={{ background: item === 'CN' ? '#ef4444' : item === 'GB' ? '#6366f1' : '#f59e0b' }} />)}</div>
          </StatCard>
          <StatCard icon={<ShieldCheck size={20} />} label="保号预警雷达" value={String(dangerCount).padStart(2, '0')} detail="张卡片需要关注" accent="rose">
            <div className="radar"><span /><span /><span /></div>
          </StatCard>
          <StatCard icon={<Zap size={20} />} label="养卡成本 / 月" value={money.format(costPerMonth)} detail="按当前汇率估算" accent="amber">
            <div className="sparkline"><i /><i /><i /><i /><i /><i /><i /></div>
          </StatCard>
          <StatCard icon={<CreditCard size={20} />} label="写卡器槽位" value="04 / 08" detail="eSTK.me · 5ber" accent="violet">
            <div className="slot-dots">{Array.from({ length: 8 }).map((_, index) => <span key={index} className={index < 4 ? 'filled' : ''} />)}</div>
          </StatCard>
        </section>

        <section className="toolbar">
          <div className="searchbox"><Search size={17} /><input placeholder="搜索运营商、号码、位置或业务..." value={query} onChange={(event) => setQuery(event.target.value)} /></div>
          <div className="filter-group">
            <div className="select-wrap"><Globe2 size={15} /><select value={country} onChange={(event) => setCountry(event.target.value)}><option value="all">所有地区</option>{countries.map((item) => <option key={item} value={item}>{countryFlags[item]} {item}</option>)}</select><ChevronDown size={14} /></div>
            <div className="select-wrap"><Filter size={15} /><select value={urgency} onChange={(event) => setUrgency(event.target.value)}><option value="all">所有状态</option><option value="danger">紧急 · 15 天内</option><option value="warning">关注 · 15-60 天</option><option value="safe">正常 · 60 天以上</option></select><ChevronDown size={14} /></div>
            <div className="view-toggle"><button className={view === 'gallery' ? 'active' : ''} onClick={() => setView('gallery')}><LayoutGrid size={16} /></button><button className={view === 'table' ? 'active' : ''} onClick={() => setView('table')}><List size={16} /></button></div>
          </div>
        </section>

        <div className="section-heading"><div><p className="eyebrow">MY COLLECTION</p><h2>{view === 'gallery' ? '卡片画廊' : '高密度卡片表格'} <span>{filtered.length}</span></h2></div><div className="legend"><span><i className="dot safe" /> 安全</span><span><i className="dot warning" /> 关注</span><span><i className="dot danger" /> 紧急</span></div></div>

        <AnimatePresence mode="popLayout">
          {view === 'gallery' ? (
            <motion.div className="card-grid" layout>
              {filtered.map((card) => <SimCardTile key={card.id} card={card} onCheckIn={checkIn} onEdit={() => { setEditing(card); setShowForm(true) }} onDelete={() => removeCard(card.id)} />)}
            </motion.div>
          ) : <TableView cards={filtered} onCheckIn={checkIn} onEdit={(card) => { setEditing(card); setShowForm(true) }} />}
        </AnimatePresence>

        {filtered.length === 0 && <div className="empty-state"><Archive size={34} /><h3>没有匹配的卡片</h3><p>换个关键词或清除筛选试试。</p></div>}
      </main>

      <AnimatePresence>{showForm && <CardForm initial={editing} onClose={() => setShowForm(false)} onSave={async (card) => { await persist(editing ? cards.map((item) => item.id === card.id ? card : item) : [...cards, card]); setShowForm(false) }} />}</AnimatePresence>
      <AnimatePresence>{notice && <motion.div initial={{ opacity: 0, y: 12 }} animate={{ opacity: 1, y: 0 }} exit={{ opacity: 0, y: 12 }} className="toast"><Check size={16} /> {notice}</motion.div>}</AnimatePresence>
    </div>
  )
}

function StatCard({ icon, label, value, detail, accent, children }: { icon: React.ReactNode; label: string; value: string; detail: string; accent: string; children: React.ReactNode }) {
  return <div className={`stat-card ${accent}`}><div className="stat-top"><span className="stat-icon">{icon}</span><span>{label}</span></div><div className="stat-value">{value}</div><div className="stat-detail">{detail}</div><div className="stat-visual">{children}</div></div>
}

function SimCardTile({ card, onCheckIn, onEdit, onDelete }: { card: SimCard; onCheckIn: (card: SimCard) => void; onEdit: () => void; onDelete: () => void }) {
  const [flipped, setFlipped] = useState(false)
  const [revealed, setRevealed] = useState(false)
  const status = statusFor(card)
  return <motion.div layout initial={{ opacity: 0, scale: .96 }} animate={{ opacity: 1, scale: 1 }} exit={{ opacity: 0, scale: .96 }} className={`sim-card-wrap ${flipped ? 'is-flipped' : ''}`} onClick={() => setFlipped(!flipped)}>
    <div className="sim-card-inner">
      <div className={`sim-card face-front theme-${card.themeColor}`}>
        <div className="corner-cut" /><div className="card-glow" />
        <div className="card-topline"><span className="country-name">{countryFlags[card.countryCode]} {card.countryCode}</span><span className="type-pill">{card.cardType === 'Physical' ? '实体 SIM' : card.cardType === 'eSIM' ? 'eSIM' : '可编程 eSIM'}</span></div>
        <div className="chip"><span /><span /><span /><span /></div>
        <div className="card-carrier">{card.carrierName}<small>{card.planName}</small></div>
        <div className="phone-number">{card.phoneNumber}<button onClick={(event) => { event.stopPropagation(); copyText(card.phoneNumber) }}><Copy size={14} /></button></div>
        <div className="card-bottom"><span className="balance">{card.currency} <strong>{card.balance.toFixed(2)}</strong></span><span className="location-badge"><MapPin size={12} /> {card.hostName}</span></div>
        <div className={`deadline ${status.color}`}><div><span>{status.label}</span><b>{dateLabel.format(new Date(card.nextDeadlineDate))}</b></div><div className="deadline-track"><i style={{ width: `${status.bar}%` }} /></div></div>
        <div className="flip-hint"><CircleHelp size={13} /> 点击查看卡背</div>
      </div>
      <div className={`sim-card face-back theme-${card.themeColor}`}>
        <div className="back-header"><span>SECURE CARD BACKSIDE</span><button onClick={(event) => { event.stopPropagation(); onEdit() }}><Settings2 size={15} /></button></div>
        <div className="secret-row"><span>ICCID</span><strong className={revealed ? '' : 'masked'}>{card.iccid}</strong><button onClick={(event) => { event.stopPropagation(); copyText(card.iccid) }}><Copy size={14} /></button></div>
        <div className="secret-row"><span>PIN / PUK</span><strong className={revealed ? '' : 'masked'}>{card.pin1} / {card.puk1}</strong><button onClick={(event) => { event.stopPropagation(); setRevealed(!revealed) }}>{revealed ? <EyeOff size={14} /> : <Eye size={14} />}</button></div>
        <div className="secret-row"><span>LPA CODE</span><strong className={revealed ? '' : 'masked'}>{card.esimLpaCode || '—'}</strong></div>
        <div className="service-label">BOUND SERVICES</div><div className="service-grid">{card.boundServices.map((tag) => <span key={tag}>{tagIcons[tag] || '•'} {tag}</span>)}</div>
        <div className="back-actions"><button className="primary-button compact" onClick={(event) => { event.stopPropagation(); onCheckIn(card) }}><ShieldCheck size={15} /> 一键打卡保号</button><button className="outline-button compact" onClick={(event) => { event.stopPropagation(); exportIcs(card) }}><CalendarDays size={15} /> .ics</button><button className="delete-icon" onClick={(event) => { event.stopPropagation(); onDelete() }}><Trash2 size={15} /></button></div>
      </div>
    </div>
  </motion.div>
}

function TableView({ cards, onCheckIn, onEdit }: { cards: SimCard[]; onCheckIn: (card: SimCard) => void; onEdit: (card: SimCard) => void }) {
  return <div className="table-shell"><table><thead><tr><th>运营商</th><th>号码</th><th>位置</th><th>余额</th><th>保号死线</th><th>操作</th></tr></thead><tbody>{cards.map((card) => { const status = statusFor(card); return <tr key={card.id}><td><b>{countryFlags[card.countryCode]} {card.carrierName}</b><small>{card.planName}</small></td><td className="mono">{card.phoneNumber}</td><td><MapPin size={13} /> {card.hostName} · {card.slotDetail}</td><td>{card.currency} {card.balance.toFixed(2)}</td><td><span className={`status-text ${status.color}`}>{status.label}</span><small>{dateLabel.format(new Date(card.nextDeadlineDate))}</small></td><td><button className="table-action" onClick={() => onCheckIn(card)}><Check size={14} /> 打卡</button><button className="table-action" onClick={() => onEdit(card)}>编辑</button></td></tr> })}</tbody></table></div>
}

function CardForm({ initial, onClose, onSave }: { initial: SimCard | null; onClose: () => void; onSave: (card: SimCard) => Promise<void> }) {
  const [form, setForm] = useState<SimCard>(initial || seedCards[0])
  const update = (key: keyof SimCard, value: string | number) => setForm((current) => ({ ...current, [key]: value }))
  return <div className="modal-backdrop" onClick={onClose}><motion.div initial={{ opacity: 0, y: 16 }} animate={{ opacity: 1, y: 0 }} className="modal" onClick={(event) => event.stopPropagation()}><div className="modal-head"><div><p className="eyebrow">CARD EDITOR</p><h2>{initial ? '编辑卡片' : '收入新卡'}</h2></div><button className="icon-button" onClick={onClose}><X size={18} /></button></div><div className="form-grid"><label>运营商<input value={form.carrierName} onChange={(event) => update('carrierName', event.target.value)} /></label><label>手机号<input value={form.phoneNumber} onChange={(event) => update('phoneNumber', event.target.value)} /></label><label>国家代码<input value={form.countryCode} maxLength={2} onChange={(event) => update('countryCode', event.target.value.toUpperCase())} /></label><label>套餐名称<input value={form.planName} onChange={(event) => update('planName', event.target.value)} /></label><label>余额<input type="number" value={form.balance} onChange={(event) => update('balance', Number(event.target.value))} /></label><label>币种<select value={form.currency} onChange={(event) => update('currency', event.target.value)}>{['CNY', 'HKD', 'GBP', 'USD', 'JPY'].map((item) => <option key={item}>{item}</option>)}</select></label><label>存放位置<input value={form.hostName} onChange={(event) => update('hostName', event.target.value)} /></label><label>卡槽详情<input value={form.slotDetail} onChange={(event) => update('slotDetail', event.target.value)} /></label><label>保号周期（天）<input type="number" value={form.keepAliveCycleDays} onChange={(event) => update('keepAliveCycleDays', Number(event.target.value))} /></label><label>保号动作<input value={form.keepAliveAction} onChange={(event) => update('keepAliveAction', event.target.value)} /></label></div><div className="modal-footer"><span><Tag size={15} /> 本地 IndexedDB 存储</span><button className="primary-button" onClick={() => onSave(form)}><Check size={17} /> 保存卡片</button></div></motion.div></div>
}

export default App
