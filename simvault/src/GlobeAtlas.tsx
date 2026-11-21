import { useEffect, useMemo, useRef, useState } from 'react'
import { geoCentroid, geoDistance, geoGraticule10, geoOrthographic, geoPath, type GeoPermissibleObjects } from 'd3-geo'
import { feature } from 'topojson-client'
import type { GeometryCollection, Topology } from 'topojson-specification'
import worldAtlas from 'world-atlas/countries-110m.json'
import type { SimCard } from './db'

const numericToIso: Record<string, string> = { '156': 'CN', '344': 'HK', '392': 'JP', '826': 'GB', '840': 'US' }
const countryFlags: Record<string, string> = { CN: '🇨🇳', GB: '🇬🇧', HK: '🇭🇰', US: '🇺🇸', JP: '🇯🇵' }
const countryNames: Record<string, string> = { CN: '中国', GB: '英国', HK: '中国香港', US: '美国', JP: '日本' }
const countryFeatures = feature(
  worldAtlas as unknown as Topology,
  (worldAtlas as unknown as Topology).objects.countries as GeometryCollection,
).features

type GlobeAtlasProps = {
  cards: SimCard[]
  paused: boolean
  focusCountry: string | null
  onSelectCountry: (countryCode: string) => void
}

type PointerState = { active: boolean; moved: boolean; x: number; y: number; rotation: [number, number, number] }

function daysUntil(date: string) {
  return Math.ceil((new Date(date).getTime() - Date.now()) / 86400000)
}

function riskFor(cards: SimCard[]) {
  const days = Math.min(...cards.map((card) => daysUntil(card.nextDeadlineDate)))
  return days < 15 ? 'danger' : days < 60 ? 'warning' : 'safe'
}

export function GlobeAtlas({ cards, paused, focusCountry, onSelectCountry }: GlobeAtlasProps) {
  const width = 780
  const height = 580
  const [rotation, setRotation] = useState<[number, number, number]>([-8, -12, 0])
  const [zoom, setZoom] = useState(1)
  const drag = useRef<PointerState>({ active: false, moved: false, x: 0, y: 0, rotation: [-8, -12, 0] })
  const animation = useRef<number | null>(null)
  const rotationRef = useRef(rotation)
  const updateRotation = (next: [number, number, number] | ((current: [number, number, number]) => [number, number, number])) => {
    const value = typeof next === 'function' ? next(rotationRef.current) : next
    rotationRef.current = value
    setRotation(value)
  }

  const projection = useMemo(() => geoOrthographic()
    .translate([width / 2, height / 2])
    .scale(220 * zoom)
    .rotate(rotation)
    .clipAngle(90), [rotation, zoom])
  const path = useMemo(() => geoPath(projection), [projection])
  const graticule = useMemo(() => geoGraticule10(), [])
  const cardsByCountry = useMemo(() => cards.reduce<Record<string, SimCard[]>>((groups, card) => {
    groups[card.countryCode] = [...(groups[card.countryCode] || []), card]
    return groups
  }, {}), [cards])
  const visibleCountries = useMemo(() => Object.keys(cardsByCountry), [cardsByCountry])

  useEffect(() => {
    if (paused) return
    const timer = window.setInterval(() => updateRotation(([longitude, latitude, roll]) => [longitude + 0.12, latitude, roll]), 60)
    return () => window.clearInterval(timer)
  }, [paused])

  useEffect(() => {
    if (!focusCountry) return
    const featureForCountry = countryFeatures.find((item) => numericToIso[String(item.id)] === focusCountry)
    if (!featureForCountry) return
    const [longitude, latitude] = geoCentroid(featureForCountry)
    const target: [number, number, number] = [-longitude, -latitude, 0]
    const start = rotationRef.current
    const startedAt = performance.now()
    if (animation.current) cancelAnimationFrame(animation.current)
    const animate = (now: number) => {
      const progress = Math.min(1, (now - startedAt) / 650)
      const eased = 1 - Math.pow(1 - progress, 3)
      updateRotation([
        start[0] + (target[0] - start[0]) * eased,
        start[1] + (target[1] - start[1]) * eased,
        0,
      ])
      if (progress < 1) animation.current = requestAnimationFrame(animate)
    }
    animation.current = requestAnimationFrame(animate)
    return () => { if (animation.current) cancelAnimationFrame(animation.current) }
  }, [focusCountry])

  const startDrag = (event: React.PointerEvent<SVGSVGElement>) => {
    drag.current = { active: true, moved: false, x: event.clientX, y: event.clientY, rotation: rotationRef.current }
    event.currentTarget.setPointerCapture(event.pointerId)
  }
  const moveDrag = (event: React.PointerEvent<SVGSVGElement>) => {
    if (!drag.current.active) return
    const dx = event.clientX - drag.current.x
    const dy = event.clientY - drag.current.y
    if (Math.hypot(dx, dy) > 5) drag.current.moved = true
    updateRotation([
      drag.current.rotation[0] + dx * 0.38,
      Math.max(-78, Math.min(78, drag.current.rotation[1] - dy * 0.25)),
      0,
    ])
  }
  const endDrag = () => {
    drag.current.active = false
    if (drag.current.moved) window.setTimeout(() => { drag.current.moved = false }, 0)
  }
  const zoomBy = (delta: number) => setZoom((value) => Math.min(3.5, Math.max(.8, Number((value + delta).toFixed(2)))))
  const reset = () => { updateRotation([-8, -12, 0]); setZoom(1) }
  const center: [number, number] = [-rotation[0], -rotation[1]]

  return (
    <div className="atlas-stage">
      <div className="atlas-atmosphere" />
      <svg className="atlas-svg" viewBox={`0 0 ${width} ${height}`} role="img" aria-label="全球 SIM 卡正射投影地图" onPointerDown={startDrag} onPointerMove={moveDrag} onPointerUp={endDrag} onPointerCancel={endDrag} onWheel={(event) => { event.preventDefault(); zoomBy(event.deltaY > 0 ? -.12 : .12) }}>
        <defs>
          <radialGradient id="atlas-sphere" cx="34%" cy="25%">
            <stop offset="0%" stopColor="#405a88" />
            <stop offset="62%" stopColor="#18263f" />
            <stop offset="100%" stopColor="#080d18" />
          </radialGradient>
          <filter id="atlas-glow"><feGaussianBlur stdDeviation="13" /></filter>
          <clipPath id="atlas-clip"><circle cx={width / 2} cy={height / 2} r={220 * zoom} /></clipPath>
        </defs>
        <circle className="atlas-glow-ring" cx={width / 2} cy={height / 2} r={220 * zoom + 12} />
        <circle className="atlas-sphere" cx={width / 2} cy={height / 2} r={220 * zoom} fill="url(#atlas-sphere)" />
        <path className="atlas-graticule" d={path(graticule) || undefined} />
        <g clipPath="url(#atlas-clip)">
          {countryFeatures.map((country, index) => {
            const iso = numericToIso[String(country.id)]
            const hasCards = Boolean(iso && cardsByCountry[iso])
            const selected = iso === focusCountry
            return <path key={country.id ?? `unnamed-${index}`} d={path(country as GeoPermissibleObjects) || undefined} className={`atlas-country ${hasCards ? 'has-cards' : ''} ${selected ? 'selected' : ''}`} onClick={() => { if (hasCards && !drag.current.moved) onSelectCountry(iso) }} />
          })}
        </g>
        {visibleCountries.map((iso) => {
          const featureForCountry = countryFeatures.find((item) => numericToIso[String(item.id)] === iso)
          if (!featureForCountry) return null
          const centroid = geoCentroid(featureForCountry)
          const point = projection(centroid)
          const visible = geoDistance(centroid, center) < Math.PI / 2
          if (!point || !visible) return null
          const countryCards = cardsByCountry[iso]
          const risk = riskFor(countryCards)
          return <g key={iso} className={`atlas-node ${focusCountry === iso ? 'active' : ''}`} transform={`translate(${point[0]} ${point[1]})`} onClick={() => { if (!drag.current.moved) onSelectCountry(iso) }}>
            <circle className={`atlas-node-pulse ${risk}`} r="15" />
            <circle className={`atlas-node-dot ${risk}`} r={focusCountry === iso ? 7 : 5} />
            <foreignObject className="atlas-node-label" x="10" y="-13" width="145" height="28">
              <span>{countryFlags[iso]} {countryNames[iso] || iso} <b>{countryCards.length}</b></span>
            </foreignObject>
          </g>
        })}
      </svg>
      <div className="atlas-controls">
        <button onClick={() => zoomBy(.25)} aria-label="放大">+</button>
        <button onClick={() => zoomBy(-.25)} aria-label="缩小">−</button>
        <button onClick={reset} aria-label="复位视角">↻</button>
        <span>{zoom.toFixed(1)}x</span>
      </div>
      <div className="atlas-console">
        <span className="atlas-live-dot" /> {paused ? '自转已暂停' : '自动自转中'} <i>·</i> 拖拽旋转 / 滚轮缩放 / 点击国家
      </div>
      <div className="atlas-coordinate">LON {center[0].toFixed(2)}° / LAT {center[1].toFixed(2)}°</div>
    </div>
  )
}
