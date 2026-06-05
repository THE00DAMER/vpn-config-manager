#!/bin/bash
# AMVFX CONFIG - AUTOMATED SETUP SCRIPT (V6 - Complete & Final)

GREEN='\033[0;32m'
BLUE='\033[0;36m'
YELLOW='\033[1;33m'
RED='\033[0;31m'
NC='\033[0m'

clear
echo -e "${GREEN}⚡️ AMVFX CONFIG SYSTEM AUTO-INSTALLER (V6)${NC}"
echo -e "${BLUE}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"

if [ "$EUID" -ne 0 ]; then
  echo -e "${RED}❌ Please run this script as root (sudo ./install.sh)${NC}"
  exit 1
fi

read -p "🌐 Enter your subdomain (e.g., yourdomain.com): " DOMAIN
read -p "🤖 Enter Telegram Bot Token: " BOT_TOKEN
read -p "👨‍💻 Enter Admin Chat IDs (comma separated, e.g., 123456,789012): " ADMIN_IDS
read -s -p "🔑 Enter a secure password for Web Panel: " PANEL_PASS
echo ""
read -p "🔌 Enter the port for Web Panel (default: 2087): " PANEL_PORT
PANEL_PORT=${PANEL_PORT:-2087}

if [ -z "$DOMAIN" ] || [ -z "$BOT_TOKEN" ] || [ -z "$ADMIN_IDS" ] || [ -z "$PANEL_PASS" ]; then
    echo -e "${RED}❌ All fields are required! Aborting.${NC}"
    exit 1
fi

if ! [[ "$PANEL_PORT" =~ ^[0-9]+$ ]] || [ "$PANEL_PORT" -lt 1024 ] || [ "$PANEL_PORT" -gt 65535 ]; then
    echo -e "${RED}❌ Invalid port! Must be between 1024 and 65535.${NC}"
    exit 1
fi

echo -e "\n${YELLOW}🔑 Paste your Cloudflare Origin Certificate (Press ENTER, then CTRL+D):${NC}"
cat > /etc/ssl/cert.pem
echo -e "\n${YELLOW}🔐 Paste your Cloudflare Private Key (Press ENTER, then CTRL+D):${NC}"
cat > /etc/ssl/key.pem

echo -e "\n${BLUE}📦 Updating system and installing dependencies...${NC}"
apt update -q
apt install -y nginx php-fpm php-curl php-json python3-venv python3-pip ufw curl wget -q

echo -e "${GREEN}✅ Dependencies installed${NC}"

PHP_VERSION=$(php -r 'echo PHP_MAJOR_VERSION."." .PHP_MINOR_VERSION;')
PHP_SOCK="/var/run/php/php${PHP_VERSION}-fpm.sock"
TARGET_DIR="/var/www/vpn_project"

echo -e "\n${BLUE}📁 Creating directories...${NC}"
mkdir -p "$TARGET_DIR"
mkdir -p "$TARGET_DIR/public_html/receipts"

if [ -d "." ]; then
    cp -r ./* "$TARGET_DIR/" 2>/dev/null || echo "⚠️  No files to copy from current directory"
fi

echo -e "${GREEN}✅ Directories created${NC}"
echo -e "\n${BLUE}📝 Creating bot.py with injected variables...${NC}"

# Create bot.py with variables injected
cat > "$TARGET_DIR/bot.py" << 'EOF'
#!/usr/bin/env python3
import json
import asyncio
import time
import os
import logging
from pathlib import Path
from aiogram import Bot, Dispatcher, types, F
from aiogram.filters import CommandStart, Command
from aiogram.fsm.context import FSMContext
from aiogram.fsm.state import StatesGroup, State
from aiogram.types import InlineKeyboardMarkup, InlineKeyboardButton
from aiogram.fsm.storage.memory import MemoryStorage

logging.basicConfig(level=logging.INFO, format='%(asctime)s - %(levelname)s - %(message)s')
logger = logging.getLogger(__name__)

BOT_TOKEN = "__BOT_TOKEN__"
ADMIN_IDS_STR = "__ADMIN_IDS__"
DATA_FILE = "/var/www/vpn_project/data.json"
RECEIPTS_DIR = "/var/www/vpn_project/public_html/receipts"

try:
    ADMIN_IDS = [int(id.strip()) for id in ADMIN_IDS_STR.split(',') if id.strip()]
    if not ADMIN_IDS:
        raise ValueError("No valid admin IDs found")
    logger.info(f"✅ Loaded {len(ADMIN_IDS)} admin IDs: {ADMIN_IDS}")
except Exception as e:
    logger.error(f"❌ Failed to parse ADMIN_IDS: {e}")
    ADMIN_IDS = []

Path(RECEIPTS_DIR).mkdir(parents=True, exist_ok=True)

if not BOT_TOKEN or BOT_TOKEN == "__BOT_TOKEN__":
    logger.error("❌ BOT_TOKEN not configured!")
    exit(1)

logger.info(f"🤖 Starting bot with token: {BOT_TOKEN[:20]}...")

bot = Bot(token=BOT_TOKEN)
storage = MemoryStorage()
dp = Dispatcher(storage=storage)

class OrderState(StatesGroup):
    waiting_for_receipt = State()

def load_data():
    try:
        if not os.path.exists(DATA_FILE):
            logger.warning(f"⚠️  {DATA_FILE} not found! Creating...")
            default_data = {"settings": {}, "plans": [], "orders": []}
            save_data(default_data)
            return default_data
        with open(DATA_FILE, 'r', encoding='utf-8') as f:
            data = json.load(f)
            logger.info(f"✅ Loaded {len(data.get('plans', []))} plans from data.json")
            return data
    except json.JSONDecodeError as e:
        logger.error(f"❌ {DATA_FILE} corrupted: {e}")
        os.rename(DATA_FILE, f"{DATA_FILE}.backup")
        default_data = {"settings": {}, "plans": [], "orders": []}
        save_data(default_data)
        return default_data
    except Exception as e:
        logger.error(f"❌ Error loading data: {e}", exc_info=True)
        return {"settings": {}, "plans": [], "orders": []}

def save_data(data):
    try:
        with open(DATA_FILE, 'w', encoding='utf-8') as f:
            json.dump(data, f, ensure_ascii=False, indent=4)
        logger.info("✅ Data saved successfully")
    except Exception as e:
        logger.error(f"❌ Error saving data: {e}", exc_info=True)

@dp.message(CommandStart())
async def start_cmd(message: types.Message):
    try:
        logger.info(f"👤 User {message.from_user.id} ({message.from_user.username}) started /start")
        data = load_data()
        welcome_text = data.get("settings", {}).get("welcome_text", "سرویس خود را انتخاب کنید:")
        plans = data.get("plans", [])
        
        logger.info(f"📊 Found {len(plans)} plans for user {message.from_user.id}")
        
        if not plans:
            logger.warning(f"⚠️  No plans available for user {message.from_user.id}")
            await message.answer("❌ درحال حاضر هیچ سرویسی موجود نیست.")
            return
        
        keyboard = [[InlineKeyboardButton(text=f"{p['name']} - {p['price']:,} تومان", callback_data=f"buy_{p['id']}")] for p in plans]
        await message.answer(welcome_text, reply_markup=InlineKeyboardMarkup(inline_keyboard=keyboard))
        logger.info(f"✅ Sent {len(plans)} plans to user {message.from_user.id}")
    except Exception as e:
        logger.error(f"❌ Error in start_cmd: {e}", exc_info=True)
        await message.answer("❌ خطای سیستمی!")

@dp.message(Command("buy"))
async def buy_cmd_handler(message: types.Message):
    try:
        logger.info(f"👤 User {message.from_user.id} used /buy")
        data = load_data()
        plans = data.get("plans", [])
        if not plans:
            await message.answer("❌ هیچ سرویسی موجود نیست.")
            return
        keyboard = [[InlineKeyboardButton(text=f"{p['name']} - {p['price']:,} تومان", callback_data=f"buy_{p['id']}")] for p in plans]
        await message.answer("🛒 لیست سرویس‌های موجود:", reply_markup=InlineKeyboardMarkup(inline_keyboard=keyboard))
    except Exception as e:
        logger.error(f"❌ Error in buy_cmd: {e}", exc_info=True)

@dp.message(Command("orders"))
async def orders_cmd_handler(message: types.Message):
    try:
        logger.info(f"👤 User {message.from_user.id} used /orders")
        data = load_data()
        user_orders = [o for o in data.get("orders", []) if o["user_id"] == message.from_user.id]
        if not user_orders:
            await message.answer("🗂 شما هنوز هیچ سفارشی ثبت نکرده‌اید.")
            return
        text = "🗂 **لیست سفارش‌های شما:**\n\n"
        for o in reversed(user_orders[-5:]):
            status_fa = "🟢 تحویل داده شده" if o["status"] == "delivered" else "⏳ در انتظار تایید"
            text += f"🔹 **شناسه:** `{o['id']}`\n📦 **سرویس:** {o['plan_name']}\n🚦 **وضعیت:** {status_fa}\n"
            if o["status"] == "delivered" and "config" in o:
                text += f"🔑 **کانفیگ:**\n`{o['config']}`\n"
            text += "───────────────\n"
        await message.answer(text, parse_mode="Markdown")
    except Exception as e:
        logger.error(f"❌ Error in orders_cmd: {e}", exc_info=True)

@dp.message(Command("support"))
async def support_cmd_handler(message: types.Message):
    try:
        data = load_data()
        support_text = data.get("settings", {}).get("support_text", "☎️ برای تماس با پشتیبانی پیام دهید.")
        await message.answer(support_text, parse_mode="Markdown")
    except Exception as e:
        logger.error(f"❌ Error in support_cmd: {e}", exc_info=True)

@dp.callback_query(F.data.startswith("buy_"))
async def process_buy(callback: types.CallbackQuery, state: FSMContext):
    try:
        plan_id = callback.data.replace("buy_", "")
        logger.info(f"👤 User {callback.from_user.id} clicked buy button for plan {plan_id}")
        data = load_data()
        selected_plan = next((p for p in data.get("plans", []) if p["id"] == plan_id), None)
        if not selected_plan:
            logger.error(f"❌ Plan {plan_id} not found")
            await callback.answer("❌ سرویس یافت نشد!")
            return
        await state.update_data(plan=selected_plan)
        await state.set_state(OrderState.waiting_for_receipt)
        payment_text = data.get("settings", {}).get("payment_text", "مبلغ: {price} تومان").replace("{price}", f"{selected_plan['price']:,}")
        await callback.message.answer(payment_text, parse_mode="Markdown")
        await callback.answer()
        logger.info(f"✅ User {callback.from_user.id} ready for {selected_plan['name']}")
    except Exception as e:
        logger.error(f"❌ Error in process_buy: {e}", exc_info=True)

@dp.message(OrderState.waiting_for_receipt, F.photo)
async def receipt_handler(message: types.Message, state: FSMContext):
    try:
        logger.info(f"📸 User {message.from_user.id} uploaded receipt")
        user_data = await state.get_data()
        if "plan" not in user_data:
            logger.error(f"❌ No plan in state for user {message.from_user.id}")
            await message.answer("❌ سفارش نامعتبر! لطفاً دوباره تلاش کنید.")
            await state.clear()
            return
        plan = user_data["plan"]
        order_id = str(int(time.time()))
        file_path = f"{RECEIPTS_DIR}/{order_id}.jpg"
        
        logger.info(f"💾 Downloading receipt to {file_path}")
        await bot.download(message.photo[-1], destination=file_path)
        
        data = load_data()
        if "orders" not in data:
            data["orders"] = []
        
        data["orders"].append({
            "id": order_id,
            "user_id": message.from_user.id,
            "username": message.from_user.username or "unknown",
            "plan_name": plan['name'],
            "amount": plan['price'],
            "status": "pending",
            "created_at": int(time.time())
        })
        save_data(data)
        
        logger.info(f"✅ Order {order_id} created for user {message.from_user.id} - Plan: {plan['name']}")
        await message.answer(f"✅ فیش شما با شناسه `{order_id}` ثبت شد. منتظر تایید ادمین باشید.", parse_mode="Markdown")
        
        # Notify admins
        for admin_id in ADMIN_IDS:
            try:
                admin_msg = f"🔔 **سفارش جدید**\n\n🔹 **شناسه:** `{order_id}`\n📦 **سرویس:** {plan['name']}\n💰 **مبلغ:** {plan['price']:,} تومان\n👤 **کاربر:** @{message.from_user.username or message.from_user.id}\n\n`/approve {order_id} vless://...`"
                await bot.send_message(admin_id, admin_msg, parse_mode="Markdown")
                logger.info(f"✅ Admin {admin_id} notified about order {order_id}")
            except Exception as e:
                logger.error(f"❌ Failed to notify admin {admin_id}: {e}")
        
        await state.clear()
    except Exception as e:
        logger.error(f"❌ Error in receipt_handler: {e}", exc_info=True)
        await message.answer("❌ خطا در ثبت سفارش!")
        await state.clear()

@dp.message(OrderState.waiting_for_receipt)
async def invalid_receipt(message: types.Message):
    logger.warning(f"⚠️  User {message.from_user.id} sent non-photo in receipt state")
    await message.answer("❌ لطفاً یک عکس ارسال کنید (نه متن).")

@dp.message(Command("admin"))
async def admin_help_cmd(message: types.Message):
    if message.from_user.id not in ADMIN_IDS:
        logger.warning(f"⚠️  Non-admin user {message.from_user.id} tried /admin")
        await message.answer("❌ شما ادمین نیستید!")
        return
    logger.info(f"👨‍💼 Admin {message.from_user.id} used /admin")
    await message.answer(
        "👨‍💻 **راهنمای ادمین:**\n\n"
        "`/approve [شناسه] [کانفیگ]`\n"
        "مثال: `/approve 1717171717 vless://xxx`\n\n"
        "`/reject [شناسه]` - رد کردن سفارش\n"
        "`/stats` - آمار فروش",
        parse_mode="Markdown"
    )

@dp.message(Command("approve"))
async def approve_cmd(message: types.Message):
    if message.from_user.id not in ADMIN_IDS:
        logger.warning(f"⚠️  Non-admin {message.from_user.id} tried /approve")
        return
    
    try:
        logger.info(f"👨‍💼 Admin {message.from_user.id} used /approve")
        args = message.text.split(maxsplit=2)
        if len(args) < 3:
            await message.answer("❌ فرمت اشتباه!\n`/approve [شناسه] [کانفیگ]`", parse_mode="Markdown")
            return
        
        order_id, config_link = args[1], args[2]
        logger.info(f"🔍 Looking for order {order_id}")
        
        data = load_data()
        order_found = False
        
        for order in data.get("orders", []):
            if order["id"] == order_id and order["status"] == "pending":
                logger.info(f"✅ Found pending order {order_id}")
                order["status"] = "delivered"
                order["config"] = config_link
                order["approved_at"] = int(time.time())
                save_data(data)
                order_found = True
                
                # Send config to user
                try:
                    user_msg = f"🎉 **سفارش شما تایید شد!**\n\n🔑 **کانفیگ شما:**\n`{config_link}`"
                    await bot.send_message(order["user_id"], user_msg, parse_mode="Markdown")
                    logger.info(f"✅ Config sent to user {order['user_id']} for order {order_id}")
                    await message.answer(f"✅ کانفیگ با موفقیت به @{order['username']} ارسال شد.")
                except Exception as e:
                    logger.error(f"❌ Failed to send config to user: {e}")
                    await message.answer(f"⚠️  کانفیگ ذخیره شد اما ارسال ناموفق: {e}")
                
                # Delete receipt file
                file_path = f"{RECEIPTS_DIR}/{order_id}.jpg"
                if os.path.exists(file_path):
                    try:
                        os.remove(file_path)
                        logger.info(f"🗑️  Deleted receipt {order_id}")
                    except Exception as e:
                        logger.error(f"❌ Failed to delete receipt: {e}")
                break
        
        if not order_found:
            logger.warning(f"⚠️  Order {order_id} not found or not pending")
            await message.answer(f"❌ سفارش `{order_id}` یافت نشد یا قبلاً تایید شده است.", parse_mode="Markdown")
    except Exception as e:
        logger.error(f"❌ Error in approve_cmd: {e}", exc_info=True)
        await message.answer(f"❌ خطا: {e}")

@dp.message(Command("reject"))
async def reject_cmd(message: types.Message):
    if message.from_user.id not in ADMIN_IDS:
        return
    try:
        logger.info(f"👨‍💼 Admin {message.from_user.id} used /reject")
        args = message.text.split(maxsplit=1)
        if len(args) < 2:
            await message.answer("❌ `/reject [شناسه]`", parse_mode="Markdown")
            return
        order_id = args[1]
        data = load_data()
        for order in data.get("orders", []):
            if order["id"] == order_id and order["status"] == "pending":
                order["status"] = "rejected"
                save_data(data)
                try:
                    await bot.send_message(order["user_id"], f"❌ سفارش شما رد شد.\n\nلطفاً برای اطلاعات /support را استفاده کنید.")
                except:
                    pass
                file_path = f"{RECEIPTS_DIR}/{order_id}.jpg"
                if os.path.exists(file_path):
                    os.remove(file_path)
                await message.answer("✅ سفارش رد شد.")
                logger.info(f"✅ Order {order_id} rejected")
                return
        await message.answer("❌ سفارش یافت نشد.")
    except Exception as e:
        logger.error(f"❌ Error in reject_cmd: {e}", exc_info=True)

@dp.message(Command("stats"))
async def stats_cmd(message: types.Message):
    if message.from_user.id not in ADMIN_IDS:
        return
    try:
        data = load_data()
        orders = data.get("orders", [])
        total = len(orders)
        delivered = len([o for o in orders if o["status"] == "delivered"])
        pending = len([o for o in orders if o["status"] == "pending"])
        rejected = len([o for o in orders if o["status"] == "rejected"])
        revenue = sum(o["amount"] for o in orders if o["status"] == "delivered")
        
        stats_msg = f"📊 **آمار سیستم:**\n\n📈 **کل سفارش‌ها:** {total}\n🟢 **تایید شده:** {delivered}\n⏳ **در انتظار:** {pending}\n❌ **رد شده:** {rejected}\n\n💰 **کل درآمد:** {revenue:,} تومان"
        await message.answer(stats_msg, parse_mode="Markdown")
        logger.info(f"📊 Admin {message.from_user.id} viewed stats")
    except Exception as e:
        logger.error(f"❌ Error in stats_cmd: {e}", exc_info=True)

async def main():
    logger.info("🚀 Bot is starting...")
    try:
        await dp.start_polling(bot, allowed_updates=dp.resolve_used_update_types())
    except Exception as e:
        logger.error(f"❌ Critical error: {e}", exc_info=True)

if __name__ == "__main__":
    try:
        asyncio.run(main())
    except KeyboardInterrupt:
        logger.info("🛑 Bot stopped by user")
    except Exception as e:
        logger.error(f"❌ Fatal error: {e}", exc_info=True)
EOF

# Replace bot.py variables
sed -i "s|__BOT_TOKEN__|${BOT_TOKEN}|g" "$TARGET_DIR/bot.py"
sed -i "s|__ADMIN_IDS__|${ADMIN_IDS}|g" "$TARGET_DIR/bot.py"

echo -e "${GREEN}✅ bot.py created${NC}"

echo -e "${BLUE}📝 Creating index.php...${NC}"
cp /dev/null "$TARGET_DIR/public_html/index.php"
echo "<?php" > "$TARGET_DIR/public_html/index.php"
echo 'session_start();' >> "$TARGET_DIR/public_html/index.php"
echo 'header("X-Content-Type-Options: nosniff");' >> "$TARGET_DIR/public_html/index.php"
echo '$admin_pass = "'$PANEL_PASS'";' >> "$TARGET_DIR/public_html/index.php"
echo '$bot_token = "'$BOT_TOKEN'";' >> "$TARGET_DIR/public_html/index.php"
echo '$data_file = "../data.json";' >> "$TARGET_DIR/public_html/index.php"
echo '$receipts_dir = "../public_html/receipts/";' >> "$TARGET_DIR/public_html/index.php"
cat >> "$TARGET_DIR/public_html/index.php" << 'PHPEOF'

if (isset($_GET['logout'])) {
    session_destroy();
    header('Location: index.php');
    exit;
}

if ($_SERVER['REQUEST_METHOD'] == 'POST' && isset($_POST['password'])) {
    if ($_POST['password'] === $admin_pass) {
        $_SESSION['logged_in'] = true;
        header('Location: index.php');
        exit;
    } else {
        $error = 'رمز عبور اشتباه است!';
    }
}

if (!isset($_SESSION['logged_in'])) {
    ?>
    <!DOCTYPE html>
    <html dir="rtl" class="dark">
    <head>
        <meta charset="UTF-8">
        <meta name="viewport" content="width=device-width, initial-scale=1.0">
        <title>ورود</title>
        <script src="https://cdn.tailwindcss.com"></script>
    </head>
    <body class="bg-gray-900 flex items-center justify-center h-screen">
        <div class="bg-gray-800 p-8 rounded-xl shadow-2xl w-96 border border-gray-700">
            <h2 class="text-2xl font-bold text-white text-center mb-6">🔐 ورود به پنل</h2>
            <?php if(isset($error)) echo "<p class='text-red-400 text-center mb-4'>$error</p>"; ?>
            <form method="POST">
                <input type="password" name="password" placeholder="رمز عبور..." class="w-full p-3 bg-gray-700 text-white rounded mb-4 border border-gray-600" required>
                <button type="submit" class="w-full bg-blue-600 hover:bg-blue-500 text-white font-bold py-3 rounded transition">ورود</button>
            </form>
        </div>
    </body>
    </html>
    <?php
    exit;
}

if (isset($_GET['view_secure_receipt'])) {
    $order_id = preg_replace('/[^0-9]/', '', $_GET['view_secure_receipt']);
    $file_path = $receipts_dir . $order_id . '.jpg';
    if (file_exists($file_path)) {
        header('Content-Type: image/jpeg');
        readfile($file_path);
        exit;
    }
    die('عکس یافت نشد');
}

$data = json_decode(file_get_contents($data_file), true);

if ($_SERVER['REQUEST_METHOD'] == 'POST' && isset($_POST['action']) && $_POST['action'] == 'approve') {
    $order_id = htmlspecialchars($_POST['order_id'], ENT_QUOTES);
    $config_link = htmlspecialchars($_POST['config_link'], ENT_QUOTES);
    
    foreach ($data['orders'] as &$order) {
        if ($order['id'] == $order_id && $order['status'] == 'pending') {
            $order['status'] = 'delivered';
            $order['config'] = $config_link;
            $order['approved_at'] = time();
            
            $msg = "🎉 سفارش شما تایید شد!\n\n🔑 کانفیگ:\n`$config_link`";
            $telegram_url = "https://api.telegram.org/bot" . $bot_token . "/sendMessage?" . http_build_query([
                'chat_id' => $order['user_id'],
                'text' => $msg,
                'parse_mode' => 'Markdown'
            ]);
            
            $ch = curl_init($telegram_url);
            curl_setopt($ch, CURLOPT_RETURNTRANSFER, true);
            curl_setopt($ch, CURLOPT_SSL_VERIFYPEER, false);
            curl_setopt($ch, CURLOPT_TIMEOUT, 10);
            $response = curl_exec($ch);
            curl_close($ch);
            
            $file_to_delete = $receipts_dir . $order_id . '.jpg';
            if (file_exists($file_to_delete)) @unlink($file_to_delete);
            break;
        }
    }
    file_put_contents($data_file, json_encode($data, JSON_UNESCAPED_UNICODE | JSON_PRETTY_PRINT));
    header('Location: index.php');
    exit;
}
?>
<!DOCTYPE html>
<html dir="rtl" class="dark">
<head>
    <meta charset="UTF-8">
    <meta name="viewport" content="width=device-width, initial-scale=1.0">
    <title>داشبورد</title>
    <script src="https://cdn.tailwindcss.com"></script>
</head>
<body class="bg-gray-900 text-gray-100 min-h-screen p-6">
    <div class="max-w-7xl mx-auto">
        <div class="flex justify-between items-center bg-gray-800 p-5 rounded-xl shadow-lg mb-8 border border-gray-700">
            <h1 class="text-2xl font-bold text-blue-400">🚀 داشبورد</h1>
            <div class="space-x-4 space-x-reverse">
                <a href="settings.php" class="bg-indigo-600 hover:bg-indigo-500 text-white px-4 py-2 rounded">⚙️ تنظیمات</a>
                <a href="?logout=1" class="bg-red-600 hover:bg-red-500 text-white px-4 py-2 rounded">خروج</a>
            </div>
        </div>
        
        <div class="bg-gray-800 rounded-xl shadow-lg border border-gray-700">
            <div class="p-4 border-b border-gray-700"><h2 class="text-lg font-bold">📥 سفارشات</h2></div>
            <div class="overflow-x-auto">
                <table class="w-full text-sm">
                    <thead class="bg-gray-700">
                        <tr><th class="p-4">شناسه</th><th class="p-4">کاربر</th><th class="p-4">سرویس</th><th class="p-4">مبلغ</th><th class="p-4">فیش</th><th class="p-4">عملیات</th></tr>
                    </thead>
                    <tbody class="divide-y divide-gray-700">
                        <?php
                        $has = false;
                        if (isset($data['orders'])) {
                            foreach (array_reverse($data['orders']) as $o) {
                                if ($o['status'] == 'pending') {
                                    $has = true;
                                    ?>
                                    <tr class="hover:bg-gray-700/50">
                                        <td class="p-4 text-xs"><?= htmlspecialchars($o['id']) ?></td>
                                        <td class="p-4">@<?= htmlspecialchars($o['username']) ?></td>
                                        <td class="p-4"><?= htmlspecialchars($o['plan_name']) ?></td>
                                        <td class="p-4"><?= number_format($o['amount']) ?></td>
                                        <td class="p-4"><a href="?view_secure_receipt=<?= htmlspecialchars($o['id']) ?>" target="_blank" class="text-blue-400">📸</a></td>
                                        <td class="p-4"><form method="POST" class="flex gap-2"><input type="hidden" name="action" value="approve"><input type="hidden" name="order_id" value="<?= htmlspecialchars($o['id']) ?>"><input type="text" name="config_link" placeholder="vless://..." required class="flex-1 bg-gray-900 text-white text-xs rounded p-1"><button type="submit" class="bg-green-600 text-white px-2 rounded">✅</button></form></td>
                                    </tr>
                                    <?php
                                }
                            }
                        }
                        if (!$has) echo '<tr><td colspan="6" class="p-8 text-center text-gray-500">هیچ سفارشی نیست</td></tr>';
                        ?>
                    </tbody>
                </table>
            </div>
        </div>
    </div>
</body>
</html>
PHPEOF

echo -e "${GREEN}✅ index.php created${NC}"
echo -e "${BLUE}📝 Creating settings.php...${NC}"
cat > "$TARGET_DIR/public_html/settings.php" << 'PHPEOF'
<?php
session_start();
if (!isset($_SESSION['logged_in'])) { header('Location: index.php'); exit; }
$data_file = '../data.json';
$data = json_decode(file_get_contents($data_file), true);
if ($_SERVER['REQUEST_METHOD'] == 'POST' && isset($_POST['action']) && $_POST['action'] == 'update_texts') {
    $data['settings']['welcome_text'] = htmlspecialchars($_POST['welcome_text'] ?? '', ENT_QUOTES, 'UTF-8');
    $data['settings']['payment_text'] = htmlspecialchars($_POST['payment_text'] ?? '', ENT_QUOTES, 'UTF-8');
    $data['settings']['support_text'] = htmlspecialchars($_POST['support_text'] ?? '', ENT_QUOTES, 'UTF-8');
    file_put_contents($data_file, json_encode($data, JSON_UNESCAPED_UNICODE | JSON_PRETTY_PRINT));
    header('Location: settings.php?msg=saved');
    exit;
}
if ($_SERVER['REQUEST_METHOD'] == 'POST' && isset($_POST['action']) && $_POST['action'] == 'add_plan') {
    $plan_name = htmlspecialchars($_POST['name'] ?? '', ENT_QUOTES, 'UTF-8');
    $plan_price = (int)($_POST['price'] ?? 0);
    if ($plan_price > 0) {
        if (!isset($data['plans'])) $data['plans'] = [];
        $data['plans'][] = ['id' => 'plan_' . time(), 'name' => $plan_name, 'price' => $plan_price];
        file_put_contents($data_file, json_encode($data, JSON_UNESCAPED_UNICODE | JSON_PRETTY_PRINT));
        header('Location: settings.php');
        exit;
    }
}
if (isset($_GET['delete'])) {
    $del_id = htmlspecialchars($_GET['delete'], ENT_QUOTES);
    $data['plans'] = array_values(array_filter($data['plans'], function($p) use ($del_id) { return $p['id'] !== $del_id; }));
    file_put_contents($data_file, json_encode($data, JSON_UNESCAPED_UNICODE | JSON_PRETTY_PRINT));
    header('Location: settings.php');
    exit;
}
?>
<!DOCTYPE html>
<html dir="rtl" class="dark">
<head>
    <meta charset="UTF-8">
    <meta name="viewport" content="width=device-width, initial-scale=1.0">
    <title>تنظیمات</title>
    <script src="https://cdn.tailwindcss.com"></script>
</head>
<body class="bg-gray-900 text-gray-100 min-h-screen p-6">
    <div class="max-w-5xl mx-auto space-y-6">
        <div class="flex justify-between items-center bg-gray-800 p-5 rounded-xl border border-gray-700">
            <h1 class="text-xl font-bold">⚙️ تنظیمات</h1>
            <a href="index.php" class="bg-gray-700 hover:bg-gray-600 text-white px-4 py-2 rounded">🔙 داشبورد</a>
        </div>
        <?php if(isset($_GET['msg'])) echo '<div class="bg-green-900/30 border border-green-600 text-green-400 p-4 rounded">✅ ذخیره شد</div>'; ?>
        <div class="grid grid-cols-1 md:grid-cols-2 gap-6">
            <div class="bg-gray-800 p-6 rounded-xl border border-gray-700">
                <h2 class="text-lg font-bold mb-4">📝 متن‌ها</h2>
                <form method="POST" class="space-y-4">
                    <input type="hidden" name="action" value="update_texts">
                    <textarea name="welcome_text" rows="3" class="w-full bg-gray-900 border border-gray-600 text-white rounded p-2" required><?= htmlspecialchars($data['settings']['welcome_text'] ?? '', ENT_QUOTES) ?></textarea>
                    <textarea name="payment_text" rows="4" class="w-full bg-gray-900 border border-gray-600 text-white rounded p-2" required><?= htmlspecialchars($data['settings']['payment_text'] ?? '', ENT_QUOTES) ?></textarea>
                    <textarea name="support_text" rows="3" class="w-full bg-gray-900 border border-gray-600 text-white rounded p-2" required><?= htmlspecialchars($data['settings']['support_text'] ?? '', ENT_QUOTES) ?></textarea>
                    <button type="submit" class="w-full bg-indigo-600 hover:bg-indigo-500 py-2 rounded">ذخیره</button>
                </form>
            </div>
            <div class="bg-gray-800 p-6 rounded-xl border border-gray-700">
                <h2 class="text-lg font-bold mb-4">➕ سرویس‌ها</h2>
                <form method="POST" class="space-y-4 mb-6">
                    <input type="hidden" name="action" value="add_plan">
                    <input type="text" name="name" placeholder="نام" required class="w-full bg-gray-900 border border-gray-600 text-white rounded p-2">
                    <input type="number" name="price" placeholder="قیمت" min="1" required class="w-full bg-gray-900 border border-gray-600 text-white rounded p-2">
                    <button type="submit" class="w-full bg-emerald-600 hover:bg-emerald-500 py-2 rounded">افزودن</button>
                </form>
                <div class="space-y-2"><?php foreach ($data['plans'] ?? [] as $p): ?><div class="flex justify-between bg-gray-900 p-3 rounded border border-gray-700"><div><div class="font-bold"><?= htmlspecialchars($p['name']) ?></div><div class="text-emerald-400 text-xs"><?= number_format($p['price']) ?> تومان</div></div><a href="?delete=<?= urlencode($p['id']) ?>" class="text-red-400 hover:text-red-300" onclick="return confirm('حذف؟')">حذف</a></div><?php endforeach; ?></div>
            </div>
        </div>
    </div>
</body>
</html>
PHPEOF

echo -e "${GREEN}✅ settings.php created${NC}"

echo -e "\n${BLUE}🔐 Setting permissions...${NC}"
chown -R www-data:www-data "$TARGET_DIR"
chmod -R 755 "$TARGET_DIR"
chmod -R 775 "$TARGET_DIR/public_html/receipts"
chmod 600 /etc/ssl/cert.pem /etc/ssl/key.pem
chmod +x "$TARGET_DIR/bot.py"

echo -e "${BLUE}🌐 Configuring Nginx...${NC}"
cat > /etc/nginx/sites-available/vpn_panel <<EOF
server {
    listen 80;
    server_name $DOMAIN;
    return 301 https://\$host:$PANEL_PORT\$request_uri;
}
server {
    listen $PANEL_PORT ssl http2;
    server_name $DOMAIN;
    ssl_certificate /etc/ssl/cert.pem;
    ssl_certificate_key /etc/ssl/key.pem;
    ssl_protocols TLSv1.2 TLSv1.3;
    ssl_ciphers HIGH:!aNULL:!MD5;
    ssl_prefer_server_ciphers on;
    root /var/www/vpn_project/public_html;
    index index.php index.html;
    location / { try_files \$uri \$uri/ /index.php?\$query_string; }
    location ~ \\.php\$ {
        include snippets/fastcgi-php.conf;
        fastcgi_pass unix:$PHP_SOCK;
    }
    location /receipts { deny all; }
}
EOF

ln -sf /etc/nginx/sites-available/vpn_panel /etc/nginx/sites-enabled/
nginx -t > /dev/null 2>&1 && systemctl restart nginx
ufw allow $PANEL_PORT/tcp > /dev/null 2>&1

echo -e "${GREEN}✅ Nginx configured${NC}"

echo -e "\n${BLUE}🐍 Setting up Python environment...${NC}"
cd "$TARGET_DIR"
rm -rf venv
python3 -m venv venv
source venv/bin/activate
pip install aiogram requests -q
deactivate

echo -e "${GREEN}✅ Python environment ready${NC}"

echo -e "\n${BLUE}⚙️  Creating Systemd service...${NC}"
cat > /etc/systemd/system/tg_bot.service <<EOF
[Unit]
Description=AMVFX Telegram Bot
After=network.target

[Service]
Type=simple
User=root
WorkingDirectory=/var/www/vpn_project
ExecStart=/var/www/vpn_project/venv/bin/python3 /var/www/vpn_project/bot.py
ExecStop=/bin/kill -9 \$MAINPID
Restart=always
RestartSec=5
KillMode=process
StandardOutput=journal
StandardError=journal

[Install]
WantedBy=multi-user.target
EOF

systemctl daemon-reload
systemctl enable tg_bot
systemctl start tg_bot

echo -e "${GREEN}✅ Service started${NC}"

sleep 3

echo -e "\n${GREEN}╔════════════════════════════════════════════════════════╗${NC}"
echo -e "${GREEN}║           🏁 نصب مکمل و موفق! 🏁                    ║${NC}"
echo -e "${GREEN}╚════════════════════════════════════════════════════════╝${NC}"
echo -e "\n${BLUE}📊 اطلاعات سیستم:${NC}"
echo -e "   🌐 پنل: ${YELLOW}https://${DOMAIN}:${PANEL_PORT}${NC}"
echo -e "   🔌 پورت: ${YELLOW}${PANEL_PORT}${NC}"
echo -e "   🤖 توکن: ${YELLOW}${BOT_TOKEN}${NC}"
echo -e "   👨‍💻 ادمین IDs: ${YELLOW}${ADMIN_IDS}${NC}"
echo -e "   🔑 رمز پنل: ${YELLOW}${PANEL_PASS}${NC}"
echo -e "\n${BLUE}📁 دایرکتوری نصب: ${YELLOW}/var/www/vpn_project${NC}"
echo -e "${BLUE}📄 فایل داده: ${YELLOW}/var/www/vpn_project/data.json${NC}"
echo -e "${BLUE}🖼️  فیش‌ها: ${YELLOW}/var/www/vpn_project/public_html/receipts${NC}"

echo -e "\n${BLUE}📋 دستورات مفید:${NC}"
echo -e "   ${YELLOW}journalctl -u tg_bot -f${NC}           # لاگ بات"
echo -e "   ${YELLOW}systemctl restart tg_bot${NC}        # راه‌اندازی مجدد بات"
echo -e "   ${YELLOW}systemctl status tg_bot${NC}          # وضعیت بات"
echo -e "   ${YELLOW}tail -50 /var/log/nginx/error.log${NC}   # خطاهای nginx"

echo -e "\n${BLUE}🔍 وضعیت خدمات:${NC}"
echo -e "${YELLOW}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
systemctl status tg_bot --no-pager | head -5
echo -e "${YELLOW}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"

echo -e "\n${GREEN}✅ همه چیز آماده است! سیستم شروع شد.${NC}\n"
