<?php
session_start();
if (!isset($_SESSION['logged_in'])) {
    header('Location: index.php');
    exit;
}

$data_file = '../data.json';
$data = json_decode(file_get_contents($data_file), true);

if ($_SERVER['REQUEST_METHOD'] == 'POST' && isset($_POST['action']) && $_POST['action'] == 'update_texts') {
    $data['settings']['welcome_text'] = htmlspecialchars($_POST['welcome_text'], ENT_QUOTES, 'UTF-8');
    $data['settings']['payment_text'] = htmlspecialchars($_POST['payment_text'], ENT_QUOTES, 'UTF-8');
    $data['settings']['support_text'] = htmlspecialchars($_POST['support_text'], ENT_QUOTES, 'UTF-8');
    
    file_put_contents($data_file, json_encode($data, JSON_UNESCAPED_UNICODE | JSON_PRETTY_PRINT));
    header('Location: settings.php?msg=saved');
    exit;
}

if ($_SERVER['REQUEST_METHOD'] == 'POST' && isset($_POST['action']) && $_POST['action'] == 'add_plan') {
    $plan_name = htmlspecialchars($_POST['name'], ENT_QUOTES, 'UTF-8');
    $plan_price = (int)$_POST['price'];
    
    if ($plan_price <= 0) {
        $error = '❌ قیمت باید بیشتر از صفر باشد!';
    } else {
        $data['plans'][] = [
            'id' => 'plan_' . time(),
            'name' => $plan_name,
            'price' => $plan_price
        ];
        file_put_contents($data_file, json_encode($data, JSON_UNESCAPED_UNICODE | JSON_PRETTY_PRINT));
        header('Location: settings.php');
        exit;
    }
}

if (isset($_GET['delete'])) {
    $del_id = htmlspecialchars($_GET['delete'], ENT_QUOTES);
    $data['plans'] = array_values(array_filter($data['plans'], function($p) use ($del_id) {
        return $p['id'] !== $del_id;
    }));
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
    <style>body { font-family: Tahoma, Arial, sans-serif; }</style>
</head>
<body class="bg-gray-900 text-gray-100 min-h-screen p-6">
    <div class="max-w-5xl mx-auto space-y-6">
        <div class="flex justify-between items-center bg-gray-800 p-5 rounded-xl border border-gray-700 shadow-lg">
            <h1 class="text-xl font-bold text-indigo-400">⚙️ تنظیمات</h1>
            <a href="index.php" class="bg-gray-700 hover:bg-gray-600 text-white px-4 py-2 rounded-lg transition">🔙 داشبورد</a>
        </div>
        
        <div class="grid grid-cols-1 md:grid-cols-2 gap-6">
            <div class="bg-gray-800 p-6 rounded-xl border border-gray-700 shadow-lg">
                <h2 class="text-lg font-bold mb-4 border-b border-gray-700 pb-2">📝 متن‌های ربات</h2>
                <?php if(isset($_GET['msg'])) echo '<p class="text-green-400 text-sm mb-4">✅ ذخیره شد.</p>'; ?>
                <form method="POST" class="space-y-4">
                    <input type="hidden" name="action" value="update_texts">
                    <div>
                        <label class="block text-sm text-gray-400 mb-1">متن صفحه اول</label>
                        <textarea name="welcome_text" rows="3" class="w-full bg-gray-900 border border-gray-600 text-white rounded p-2 focus:border-blue-500" required><?= htmlspecialchars($data['settings']['welcome_text'] ?? '') ?></textarea>
                    </div>
                    <div>
                        <label class="block text-sm text-gray-400 mb-1">متن پرداخت ({price} = مبلغ)</label>
                        <textarea name="payment_text" rows="4" class="w-full bg-gray-900 border border-gray-600 text-white rounded p-2 focus:border-blue-500" required><?= htmlspecialchars($data['settings']['payment_text'] ?? '') ?></textarea>
                    </div>
                    <div>
                        <label class="block text-sm text-gray-400 mb-1">متن پشتیبانی</label>
                        <textarea name="support_text" rows="2" class="w-full bg-gray-900 border border-gray-600 text-white rounded p-2 focus:border-blue-500" required><?= htmlspecialchars($data['settings']['support_text'] ?? '') ?></textarea>
                    </div>
                    <button type="submit" class="w-full bg-indigo-600 hover:bg-indigo-500 py-2 rounded font-medium transition">ذخیره متن‌ها</button>
                </form>
            </div>
            
            <div class="bg-gray-800 p-6 rounded-xl border border-gray-700 shadow-lg">
                <h2 class="text-lg font-bold mb-4 border-b border-gray-700 pb-2">➕ افزودن سرویس</h2>
                <?php if(isset($error)) echo "<p class='text-red-400 text-sm mb-4'>$error</p>"; ?>
                <form method="POST" class="space-y-4 mb-6">
                    <input type="hidden" name="action" value="add_plan">
                    <input type="text" name="name" placeholder="نام پلن" required class="w-full bg-gray-900 border border-gray-600 text-white rounded p-2 focus:border-blue-500">
                    <input type="number" name="price" placeholder="قیمت (تومان)" min="1" required class="w-full bg-gray-900 border border-gray-600 text-white rounded p-2 focus:border-blue-500">
                    <button type="submit" class="w-full bg-emerald-600 hover:bg-emerald-500 py-2 rounded font-medium transition">افزودن</button>
                </form>
                
                <div class="space-y-2">
                    <?php foreach ($data['plans'] as $plan): ?>
                    <div class="flex justify-between items-center bg-gray-900 p-3 rounded border border-gray-700">
                        <div>
                            <div class="text-white font-bold"><?= htmlspecialchars($plan['name']) ?></div>
                            <div class="text-emerald-400 text-xs"><?= number_format($plan['price']) ?> تومان</div>
                        </div>
                        <a href="?delete=<?= urlencode($plan['id']) ?>" class="text-red-400 bg-red-400/10 hover:bg-red-400/20 px-2 py-1 rounded transition" onclick="return confirm('آیا مطمئنید؟')">حذف</a>
                    </div>
                    <?php endforeach; ?>
                </div>
            </div>
        </div>
    </div>
</body>
</html>
