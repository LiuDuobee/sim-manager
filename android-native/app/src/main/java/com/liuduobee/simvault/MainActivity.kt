package com.liuduobee.simvault

import android.os.Bundle
import androidx.activity.ComponentActivity
import androidx.activity.compose.setContent
import androidx.compose.animation.core.animateFloatAsState
import androidx.compose.foundation.Canvas
import androidx.compose.foundation.background
import androidx.compose.foundation.gestures.detectTransformGestures
import androidx.compose.foundation.horizontalScroll
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.layout.width
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.foundation.verticalScroll
import androidx.compose.material3.AssistChip
import androidx.compose.material3.Badge
import androidx.compose.material3.Button
import androidx.compose.material3.Card
import androidx.compose.material3.CardDefaults
import androidx.compose.material3.FilterChip
import androidx.compose.material3.HorizontalDivider
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.Scaffold
import androidx.compose.material3.Surface
import androidx.compose.material3.Text
import androidx.compose.material3.darkColorScheme
import androidx.compose.runtime.Composable
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableFloatStateOf
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.setValue
import androidx.compose.runtime.collectAsState
import androidx.compose.ui.input.pointer.pointerInput
import androidx.compose.ui.Modifier
import androidx.compose.ui.unit.dp
import androidx.lifecycle.ViewModel
import androidx.lifecycle.viewmodel.compose.viewModel
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.StateFlow
import kotlinx.coroutines.flow.asStateFlow
import java.time.LocalDate
import kotlin.math.cos
import kotlin.math.min
import kotlin.math.sin

data class SimCard(
    val id: String,
    val phoneNumber: String,
    val carrierName: String,
    val countryCode: String,
    val cardType: String,
    val themeColor: String,
    val locationType: String,
    val hostName: String,
    val slotDetail: String,
    val isActive: Boolean,
    val planName: String,
    val balance: Double,
    val currency: String,
    val billingCycle: String,
    val cycleCost: Double,
    val cnyMonthlyEstimate: Double,
    val keepAliveCycleDays: Int,
    val keepAliveAction: String,
    val nextDeadlineDate: LocalDate,
    val boundServices: List<String>,
)

enum class CapabilityMode(val label: String) {
    STANDARD("STANDARD"),
    SHIZUKU("SHIZUKU"),
    APDU("APDU"),
}

interface SimCapabilityProvider {
    val mode: CapabilityMode
    fun describe(): String
}

class StandardEngine : SimCapabilityProvider {
    override val mode = CapabilityMode.STANDARD
    override fun describe() = "SubscriptionManager · 基础双卡信息"
}

class ShizukuEngine : SimCapabilityProvider {
    override val mode = CapabilityMode.SHIZUKU
    override fun describe() = "等待 Shizuku 授权 · 免 Root 扩展能力"
}

class PrivilegedApduEngine : SimCapabilityProvider {
    override val mode = CapabilityMode.APDU
    override fun describe() = "OMAPI / APDU · 写卡器能力待授权"
}

sealed interface SimVaultIntent {
    data class SelectMode(val mode: CapabilityMode) : SimVaultIntent
    data class SelectCountry(val country: String) : SimVaultIntent
    data object ToggleRotation : SimVaultIntent
}

data class SimVaultUiState(
    val cards: List<SimCard> = sampleCards(),
    val selectedCountry: String = "ALL",
    val capabilityMode: CapabilityMode = CapabilityMode.STANDARD,
    val autoRotate: Boolean = true,
)

class SimVaultViewModel : ViewModel() {
    private val _state = MutableStateFlow(SimVaultUiState())
    val state: StateFlow<SimVaultUiState> = _state.asStateFlow()

    fun onIntent(intent: SimVaultIntent) {
        _state.value = when (intent) {
            is SimVaultIntent.SelectCountry -> _state.value.copy(selectedCountry = intent.country)
            is SimVaultIntent.SelectMode -> _state.value.copy(capabilityMode = intent.mode)
            SimVaultIntent.ToggleRotation -> _state.value.copy(autoRotate = !_state.value.autoRotate)
        }
    }
}

class MainActivity : ComponentActivity() {
    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        setContent { SimVaultApp() }
    }
}

@Composable
fun SimVaultApp(viewModel: SimVaultViewModel = viewModel()) {
    val state by viewModel.state.collectAsState()
    MaterialTheme(colorScheme = darkColorScheme(
        primary = androidx.compose.ui.graphics.Color(0xFF6DC8FF),
        secondary = androidx.compose.ui.graphics.Color(0xFFFFB45C),
        background = androidx.compose.ui.graphics.Color(0xFF07090E),
        surface = androidx.compose.ui.graphics.Color(0xFF0F1420),
    )) {
        Scaffold(containerColor = androidx.compose.ui.graphics.Color(0xFF07090E)) { padding ->
            Column(
                modifier = Modifier.fillMaxSize().padding(padding).padding(horizontal = 16.dp),
            ) {
                Header(state, viewModel::onIntent)
                HudGlobe(
                    cards = state.cards,
                    autoRotate = state.autoRotate,
                    modifier = Modifier.fillMaxWidth().height(330.dp),
                )
                RadarAndBento(state, viewModel::onIntent)
            }
        }
    }
}

@Composable
private fun Header(state: SimVaultUiState, dispatch: (SimVaultIntent) -> Unit) {
    Column(modifier = Modifier.padding(top = 12.dp, bottom = 10.dp)) {
        Row(verticalAlignment = androidx.compose.ui.Alignment.CenterVertically) {
            Column(modifier = Modifier.weight(1f)) {
                Text("SIMVault", style = MaterialTheme.typography.headlineSmall)
                Text(
                    "NATIVE CARD ATLAS · v3.1.0",
                    color = androidx.compose.ui.graphics.Color(0xFF8294AA),
                    style = MaterialTheme.typography.labelSmall,
                )
            }
            Badge(containerColor = androidx.compose.ui.graphics.Color(0xFF1D604F)) {
                Text("LOCAL", modifier = Modifier.padding(horizontal = 8.dp, vertical = 4.dp))
            }
        }
        Spacer(Modifier.height(12.dp))
        Row(
            modifier = Modifier.horizontalScroll(rememberScrollState()),
            horizontalArrangement = Arrangement.spacedBy(8.dp),
        ) {
            listOf("ALL", "CN", "GB", "HK", "US", "JP").forEach { country ->
                FilterChip(
                    selected = state.selectedCountry == country,
                    onClick = { dispatch(SimVaultIntent.SelectCountry(country)) },
                    label = { Text(country) },
                )
            }
        }
    }
}

@Composable
private fun HudGlobe(cards: List<SimCard>, autoRotate: Boolean, modifier: androidx.compose.ui.Modifier) {
    var rotation by remember { mutableFloatStateOf(-0.5f) }
    var zoom by remember { mutableFloatStateOf(1f) }
    val animatedRotation by animateFloatAsState(
        targetValue = if (autoRotate) rotation + 0.02f else rotation,
        label = "globe-rotation",
    )
    Box(modifier = modifier.background(
        androidx.compose.ui.graphics.Color(0xFF0A111C),
        RoundedCornerShape(26.dp),
    )) {
        Canvas(
            modifier = Modifier.fillMaxSize().pointerInput(Unit) {
                detectTransformGestures { _, pan, gestureZoom, _ ->
                    rotation += pan.x / 480f
                    zoom = (zoom * gestureZoom).coerceIn(.8f, 1.65f)
                }
            },
        ) {
            drawGlobe(animatedRotation, zoom, cards)
        }
        Text(
            "WORLD CARD ATLAS",
            modifier = Modifier.align(androidx.compose.ui.Alignment.TopStart).padding(16.dp),
            color = androidx.compose.ui.graphics.Color(0xFF9AB4D0),
            style = MaterialTheme.typography.labelMedium,
        )
        Text(
            "拖拽旋转 · 双指缩放",
            modifier = Modifier.align(androidx.compose.ui.Alignment.BottomEnd).padding(14.dp),
            color = androidx.compose.ui.graphics.Color(0xFF718399),
            style = MaterialTheme.typography.labelSmall,
        )
    }
}

private fun androidx.compose.ui.graphics.drawscope.DrawScope.drawGlobe(
    rotation: Float,
    zoom: Float,
    cards: List<SimCard>,
) {
    val center = androidx.compose.ui.geometry.Offset(size.width / 2, size.height / 2)
    val radius = min(size.width, size.height) * .34f * zoom
    drawCircle(
        brush = androidx.compose.ui.graphics.Brush.radialGradient(
            listOf(androidx.compose.ui.graphics.Color(0xFF24445D), androidx.compose.ui.graphics.Color(0xFF070A11)),
            center = center,
            radius = radius,
        ),
        radius = radius,
        center = center,
    )
    repeat(7) { index ->
        val y = center.y + radius * (index - 3) / 4
        drawOval(
            color = androidx.compose.ui.graphics.Color(0x553F82B8),
            topLeft = androidx.compose.ui.geometry.Offset(center.x - radius * .9f, y - radius * .1f),
            size = androidx.compose.ui.geometry.Size(radius * 1.8f, radius * .2f),
            style = androidx.compose.ui.graphics.drawscope.Stroke(1f),
        )
    }
    repeat(8) { index ->
        val x = center.x + radius * sin(rotation + index * Math.PI / 4).toFloat()
        drawOval(
            color = androidx.compose.ui.graphics.Color(0x553F82B8),
            topLeft = androidx.compose.ui.geometry.Offset(x - radius * .08f, center.y - radius),
            size = androidx.compose.ui.geometry.Size(radius * .16f, radius * 2),
            style = androidx.compose.ui.graphics.drawscope.Stroke(1f),
        )
    }
    val points = mapOf(
        "CN" to Pair(.52f, -.05f),
        "GB" to Pair(.1f, -.45f),
        "HK" to Pair(.58f, .06f),
        "US" to Pair(-.5f, -.1f),
        "JP" to Pair(.7f, -.02f),
    )
    cards.distinctBy { it.countryCode }.forEach { card ->
        val point = points[card.countryCode] ?: return@forEach
        val x = center.x + point.first * radius + sin(rotation) * radius * .08f
        val y = center.y + point.second * radius
        drawCircle(androidx.compose.ui.graphics.Color(0xFFFFB45C), 5f, androidx.compose.ui.geometry.Offset(x, y))
        drawCircle(
            androidx.compose.ui.graphics.Color(0x55FFB45C),
            12f,
            androidx.compose.ui.geometry.Offset(x, y),
            style = androidx.compose.ui.graphics.drawscope.Stroke(1f),
        )
    }
}

@Composable
private fun RadarAndBento(state: SimVaultUiState, dispatch: (SimVaultIntent) -> Unit) {
    val filtered = if (state.selectedCountry == "ALL") state.cards else state.cards.filter { it.countryCode == state.selectedCountry }
    Column(modifier = Modifier.padding(top = 14.dp).verticalScroll(rememberScrollState())) {
        Row(horizontalArrangement = Arrangement.spacedBy(8.dp)) {
            Metric("CARDS", "${state.cards.size}", Modifier.weight(1f))
            Metric("RADAR", "${state.cards.count { it.nextDeadlineDate.isBefore(LocalDate.now().plusDays(30)) }}", Modifier.weight(1f))
            Metric("REGIONS", "${state.cards.map { it.countryCode }.distinct().size}", Modifier.weight(1f))
        }
        Spacer(Modifier.height(14.dp))
        Card(
            colors = CardDefaults.cardColors(containerColor = androidx.compose.ui.graphics.Color(0xFF0F1420)),
            shape = RoundedCornerShape(18.dp),
        ) {
            Column(Modifier.padding(14.dp)) {
                Row(verticalAlignment = androidx.compose.ui.Alignment.CenterVertically) {
                    Text("KEEP-ALIVE RADAR", style = MaterialTheme.typography.labelLarge)
                    Spacer(Modifier.weight(1f))
                    AssistChip(
                        onClick = { dispatch(SimVaultIntent.ToggleRotation) },
                        label = { Text(if (state.autoRotate) "AUTO" else "PAUSED") },
                    )
                }
                HorizontalDivider(Modifier.padding(vertical = 8.dp), color = androidx.compose.ui.graphics.Color(0x1FFFFFFF))
                filtered.sortedBy { it.nextDeadlineDate }.take(4).forEach { card ->
                    val days = java.time.temporal.ChronoUnit.DAYS.between(LocalDate.now(), card.nextDeadlineDate)
                    val priority = if (days < 15) "P1" else if (days < 60) "P2" else "OK"
                    Row(
                        modifier = Modifier.fillMaxWidth().padding(vertical = 7.dp),
                        verticalAlignment = androidx.compose.ui.Alignment.CenterVertically,
                    ) {
                        Text(card.countryCode, modifier = Modifier.width(34.dp), color = androidx.compose.ui.graphics.Color(0xFFFFB45C))
                        Column(Modifier.weight(1f)) {
                            Text(card.carrierName)
                            Text("${card.hostName} · ${days.coerceAtLeast(0)} 天后死线", color = androidx.compose.ui.graphics.Color(0xFF8294AA), style = MaterialTheme.typography.labelSmall)
                        }
                        Text(priority, color = if (priority == "P1") androidx.compose.ui.graphics.Color(0xFFFF7185) else androidx.compose.ui.graphics.Color(0xFFFFB45C))
                    }
                }
            }
        }
    }
}

@Composable
private fun Metric(label: String, value: String, modifier: androidx.compose.ui.Modifier) {
    Card(
        modifier = modifier,
        colors = CardDefaults.cardColors(containerColor = androidx.compose.ui.graphics.Color(0xFF0F1420)),
    ) {
        Column(Modifier.padding(12.dp)) {
            Text(label, color = androidx.compose.ui.graphics.Color(0xFF8294AA), style = MaterialTheme.typography.labelSmall)
            Text(value, color = androidx.compose.ui.graphics.Color(0xFF6DC8FF), style = MaterialTheme.typography.headlineSmall)
        }
    }
}

private fun sampleCards() = listOf(
    SimCard("cn", "+86 138 0013 8000", "中国移动", "CN", "Physical", "ocean", "Device", "iPhone 主卡", "Slot 1", true, "8 元保号", 42.8, "CNY", "Monthly", 8.0, 8.0, 180, "发一条短信", LocalDate.now().plusDays(26), listOf("Telegram", "银行卡")),
    SimCard("gb", "+44 7400 123456", "giffgaff", "GB", "eSIM", "violet", "Device", "iPhone 副卡", "Profile 2", false, "Pay As You Go", 15.2, "GBP", "PayGo", 0.0, 12.0, 180, "发送短信", LocalDate.now().plusDays(142), listOf("Google")),
    SimCard("hk", "+852 5123 8888", "Club SIM", "HK", "Physical", "amber", "Binder", "卡册 A 区", "第2页-第4格", false, "年费保号", 108.0, "HKD", "Yearly", 108.0, 9.0, 365, "充值任意金额", LocalDate.now().plusDays(70), listOf("Telegram", "银行卡")),
    SimCard("us", "+1 213 555 0198", "T-Mobile", "US", "Programmable_eSIM", "cyan", "SmartCard", "eSTK.me #1", "Profile 3", true, "Connect 5GB", 12.0, "USD", "Monthly", 12.0, 85.0, 30, "产生一次流量", LocalDate.now().plusDays(12), listOf("Google")),
    SimCard("jp", "+81 70 1234 5678", "Rakuten", "JP", "eSIM", "red", "Binder", "卡册 B 区", "第1页-第2格", false, "Rakuten 最低月租", 680.0, "JPY", "Monthly", 680.0, 32.0, 180, "发送短信", LocalDate.now().plusDays(78), listOf("Google")),
)
