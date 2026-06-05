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

logger.info(f"🤖 Bot Token: {BOT_TOKEN[:20]}...")

bot = Bot(token=BOT_TOKEN)
storage = MemoryStorage()
dp = Dispatcher(storage=storage)

class OrderState(StatesGroup):
    waiting_for_receipt = State()

def load_data():
    try:
        if not os.path.exists(DATA_FILE):
            logger.warning(f"⚠️ {DATA_FILE} not found! Creating...")
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
            logger.warning(f"⚠️ No plans available for user {message.from_user.id}")
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
        logger.info(f"✅ User {callback.from_user.id} ready to upload receipt for {selected_plan['name']}")
    except Exception as e:
        logger.error(f"❌ Error in process_buy: {e}", exc_info=True)

@dp.message(OrderState.waiting_for_receipt, F.photo)
async def receipt_handler(message: types.Message, state: FSMContext):
    try:
        logger.info(f"📸 User {message.from_user.id} uploaded receipt photo")
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
    logger.warning(f"⚠️ User {message.from_user.id} sent non-photo message in receipt state")
    await message.answer("❌ لطفاً یک عکس ارسال کنید (نه متن).")

@dp.message(Command("admin"))
async def admin_help_cmd(message: types.Message):
    if message.from_user.id not in ADMIN_IDS:
        logger.warning(f"⚠️ Non-admin user {message.from_user.id} tried /admin")
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
        logger.warning(f"⚠️ Non-admin {message.from_user.id} tried /approve")
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
                    logger.error(f"❌ Failed to send config to user {order['user_id']}: {e}")
                    await message.answer(f"⚠️ کانفیگ ذخیره شد اما ارسال ناموفق: {e}")
                
                # Delete receipt file
                file_path = f"{RECEIPTS_DIR}/{order_id}.jpg"
                if os.path.exists(file_path):
                    try:
                        os.remove(file_path)
                        logger.info(f"🗑️ Deleted receipt {order_id}")
                    except Exception as e:
                        logger.error(f"❌ Failed to delete receipt: {e}")
                break
        
        if not order_found:
            logger.warning(f"⚠️ Order {order_id} not found or not pending")
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
