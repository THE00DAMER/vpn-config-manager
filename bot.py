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

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

BOT_TOKEN = "__BOT_TOKEN__"
ADMIN_IDS_STR = "__ADMIN_IDS__"
DATA_FILE = "/var/www/vpn_project/data.json"
RECEIPTS_DIR = "/var/www/vpn_project/public_html/receipts"

try:
    ADMIN_IDS = [int(id.strip()) for id in ADMIN_IDS_STR.split(',') if id.strip()]
    if not ADMIN_IDS:
        raise ValueError("No valid admin IDs found")
    logger.info(f"✅ Loaded {len(ADMIN_IDS)} admin IDs")
except Exception as e:
    logger.error(f"❌ Failed to parse ADMIN_IDS: {e}")
    ADMIN_IDS = []

Path(RECEIPTS_DIR).mkdir(parents=True, exist_ok=True)

if not BOT_TOKEN or BOT_TOKEN == "__BOT_TOKEN__":
    logger.error("❌ BOT_TOKEN not configured!")
    exit(1)

logger.info(f"🚀 Starting bot...")

bot = Bot(token=BOT_TOKEN)
storage = MemoryStorage()
dp = Dispatcher(storage=storage)

class OrderState(StatesGroup):
    waiting_for_receipt = State()

def load_data():
    try:
        if not os.path.exists(DATA_FILE):
            logger.warning(f"⚠️  {DATA_FILE} not found!")
            default_data = {"settings": {}, "plans": [], "orders": []}
            save_data(default_data)
            return default_data
        with open(DATA_FILE, 'r', encoding='utf-8') as f:
            data = json.load(f)
            logger.info(f"✅ Loaded {len(data.get('plans', []))} plans")
            return data
    except json.JSONDecodeError:
        logger.error(f"❌ {DATA_FILE} corrupted!")
        os.rename(DATA_FILE, f"{DATA_FILE}.backup")
        default_data = {"settings": {}, "plans": [], "orders": []}
        save_data(default_data)
        return default_data
    except Exception as e:
        logger.error(f"❌ Error: {e}")
        return {"settings": {}, "plans": [], "orders": []}

def save_data(data):
    try:
        with open(DATA_FILE, 'w', encoding='utf-8') as f:
            json.dump(data, f, ensure_ascii=False, indent=4)
    except Exception as e:
        logger.error(f"❌ Error saving: {e}")

@dp.message(CommandStart())
async def start_cmd(message: types.Message):
    try:
        data = load_data()
        welcome_text = data.get("settings", {}).get("welcome_text", "سرویس خود را انتخاب کنید:")
        plans = data.get("plans", [])
        
        if not plans:
            await message.answer("❌ درحال حاضر هیچ سرویسی موجود نیست.")
            return
        
        keyboard = [[InlineKeyboardButton(text=f"{p['name']} - {p['price']:,} تومان", callback_data=f"buy_{p['id']}")] for p in plans]
        await message.answer(welcome_text, reply_markup=InlineKeyboardMarkup(inline_keyboard=keyboard))
    except Exception as e:
        logger.error(f"❌ Error: {e}")
        await message.answer("❌ خطا!")

@dp.message(Command("buy"))
async def buy_cmd_handler(message: types.Message):
    try:
        data = load_data()
        plans = data.get("plans", [])
        if not plans:
            await message.answer("❌ هیچ سرویسی موجود نیست.")
            return
        keyboard = [[InlineKeyboardButton(text=f"{p['name']} - {p['price']:,} تومان", callback_data=f"buy_{p['id']}")] for p in plans]
        await message.answer("🛒 لیست سرویس‌ها:", reply_markup=InlineKeyboardMarkup(inline_keyboard=keyboard))
    except Exception as e:
        logger.error(f"❌ Error: {e}")

@dp.message(Command("orders"))
async def orders_cmd_handler(message: types.Message):
    try:
        data = load_data()
        user_orders = [o for o in data.get("orders", []) if o["user_id"] == message.from_user.id]
        if not user_orders:
            await message.answer("🗂 شما سفارشی ندارید.")
            return
        text = "🗂 **سفارش‌های شما:**\n\n"
        for o in reversed(user_orders[-5:]):
            status = "🟢" if o["status"] == "delivered" else "⏳"
            text += f"{status} {o['id']}\n📦 {o['plan_name']}\n"
        await message.answer(text, parse_mode="Markdown")
    except Exception as e:
        logger.error(f"❌ Error: {e}")

@dp.callback_query(F.data.startswith("buy_"))
async def process_buy(callback: types.CallbackQuery, state: FSMContext):
    try:
        plan_id = callback.data.replace("buy_", "")
        data = load_data()
        plan = next((p for p in data.get("plans", []) if p["id"] == plan_id), None)
        if not plan:
            return
        await state.update_data(plan=plan)
        await state.set_state(OrderState.waiting_for_receipt)
        payment_text = data.get("settings", {}).get("payment_text", "مبلغ: {price}").replace("{price}", f"{plan['price']:,}")
        await callback.message.answer(payment_text, parse_mode="Markdown")
    except Exception as e:
        logger.error(f"❌ Error: {e}")

@dp.message(OrderState.waiting_for_receipt, F.photo)
async def receipt_handler(message: types.Message, state: FSMContext):
    try:
        user_data = await state.get_data()
        if "plan" not in user_data:
            await state.clear()
            return
        plan = user_data["plan"]
        order_id = str(int(time.time()))
        file_path = f"{RECEIPTS_DIR}/{order_id}.jpg"
        await bot.download(message.photo[-1], destination=file_path)
        data = load_data()
        data.get("orders", []).append({
            "id": order_id,
            "user_id": message.from_user.id,
            "username": message.from_user.username or "unknown",
            "plan_name": plan['name'],
            "amount": plan['price'],
            "status": "pending"
        })
        save_data(data)
        await message.answer(f"✅ ثبت: `{order_id}`", parse_mode="Markdown")
        for admin_id in ADMIN_IDS:
            try:
                await bot.send_message(admin_id, f"🔔 {order_id}\n{plan['name']}\n/approve {order_id} vless://...")
            except:
                pass
        await state.clear()
    except Exception as e:
        logger.error(f"❌ Error: {e}")
        await state.clear()

@dp.message(Command("approve"))
async def approve_cmd(message: types.Message):
    if message.from_user.id not in ADMIN_IDS:
        return
    try:
        args = message.text.split(maxsplit=2)
        if len(args) < 3:
            return
        order_id, config = args[1], args[2]
        data = load_data()
        for order in data.get("orders", []):
            if order["id"] == order_id and order["status"] == "pending":
                order["status"] = "delivered"
                order["config"] = config
                save_data(data)
                try:
                    await bot.send_message(order["user_id"], f"🎉 سفارش شما تایید شد!\n`{config}`", parse_mode="Markdown")
                except:
                    pass
                return
    except Exception as e:
        logger.error(f"❌ Error: {e}")

async def main():
    logger.info("🚀 Bot running...")
    await dp.start_polling(bot)

if __name__ == "__main__":
    asyncio.run(main())
