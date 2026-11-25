<?php
/**
 * SSB Inventory – list items, add an item, edit an item.
 *
 *   GET  index.php            list + empty "Add item" form
 *   GET  index.php?edit=ID    list + form pre-filled with that item
 *   POST action=create        insert, then redirect (Post/Redirect/Get)
 *   POST action=update        update, then redirect
 */
declare(strict_types=1);

require __DIR__ . '/inc/bootstrap.php';

start_session();

$errors = [];
$editId = null;
$form   = ['sku' => '', 'name' => '', 'category' => 'General', 'quantity' => '0', 'unit_price' => '0.00'];

if ($_SERVER['REQUEST_METHOD'] === 'POST') {
    verify_csrf();

    $action = $_POST['action'] ?? '';
    $form   = item_form_from($_POST);
    $errors = validate_item($form);

    if ($action === 'update') {
        $editId = filter_var($_POST['id'] ?? null, FILTER_VALIDATE_INT, ['options' => ['min_range' => 1]]) ?: null;
        if ($editId === null || find_item($editId) === null) {
            flash('That item no longer exists.', 'error');
            redirect('index.php');
        }
    } elseif ($action !== 'create') {
        http_response_code(400);
        exit('Unknown action.');
    }

    if (!$errors) {
        try {
            if ($action === 'create') {
                create_item($form);
                flash("Item {$form['sku']} added.");
            } else {
                update_item($editId, $form);
                flash("Item {$form['sku']} updated.");
            }
            redirect('index.php');
        } catch (PDOException $e) {
            // 23000 = integrity constraint violation → the UNIQUE key on sku
            if ($e->getCode() !== '23000') {
                throw $e;
            }
            $errors[] = "SKU {$form['sku']} already exists – choose another.";
        }
    }
} elseif (isset($_GET['edit'])) {
    $editId = filter_var($_GET['edit'], FILTER_VALIDATE_INT, ['options' => ['min_range' => 1]]) ?: null;
    $item   = $editId ? find_item($editId) : null;
    if ($item === null) {
        flash('Item not found.', 'error');
        redirect('index.php');
    }
    $form = item_form_from($item);
}

$items     = all_items();
$flashMsg  = take_flash();
$isEditing = $editId !== null;
$lowStock  = 5;
?>
<!doctype html>
<html lang="en">
<head>
    <meta charset="utf-8">
    <meta name="viewport" content="width=device-width, initial-scale=1">
    <title>SSB Inventory</title>
    <link rel="stylesheet" href="assets/style.css">
</head>
<body>
<main class="container">
    <header class="page-head">
        <h1>SSB Inventory</h1>
        <p class="muted"><?= count($items) ?> items · database <code><?= e(app_config()['DB_NAME']) ?></code>
            as <code><?= e(app_config()['DB_USER']) ?></code></p>
    </header>

    <?php if ($flashMsg): ?>
        <div class="flash flash-<?= e($flashMsg['type']) ?>"><?= e($flashMsg['message']) ?></div>
    <?php endif; ?>

    <section>
        <h2>Items</h2>
        <div class="table-wrap">
            <table>
                <thead>
                <tr>
                    <th>ID</th><th>SKU</th><th>Name</th><th>Category</th>
                    <th class="num">Qty</th><th class="num">Unit price (₹)</th><th>Updated</th><th></th>
                </tr>
                </thead>
                <tbody>
                <?php foreach ($items as $item): ?>
                    <tr class="<?= (int) $item['id'] === $editId ? 'editing' : '' ?>">
                        <td><?= e($item['id']) ?></td>
                        <td><code><?= e($item['sku']) ?></code></td>
                        <td><?= e($item['name']) ?></td>
                        <td><?= e($item['category']) ?></td>
                        <td class="num<?= $item['quantity'] < $lowStock ? ' low' : '' ?>"><?= e($item['quantity']) ?></td>
                        <td class="num"><?= e(number_format((float) $item['unit_price'], 2)) ?></td>
                        <td class="muted"><?= e($item['updated_at']) ?></td>
                        <td><a href="index.php?edit=<?= e($item['id']) ?>">Edit</a></td>
                    </tr>
                <?php endforeach; ?>
                <?php if (!$items): ?>
                    <tr><td colspan="8" class="muted">No items yet – add one below.</td></tr>
                <?php endif; ?>
                </tbody>
            </table>
        </div>
        <p class="muted small">Quantity in <span class="low">red</span> = fewer than <?= $lowStock ?> left.</p>
    </section>

    <section class="card">
        <h2><?= $isEditing ? 'Edit item #' . e($editId) : 'Add item' ?></h2>

        <?php if ($errors): ?>
            <div class="flash flash-error">
                <ul><?php foreach ($errors as $err): ?><li><?= e($err) ?></li><?php endforeach; ?></ul>
            </div>
        <?php endif; ?>

        <form method="post" action="index.php<?= $isEditing ? '?edit=' . e($editId) : '' ?>" class="item-form">
            <input type="hidden" name="csrf" value="<?= e(csrf_token()) ?>">
            <input type="hidden" name="action" value="<?= $isEditing ? 'update' : 'create' ?>">
            <?php if ($isEditing): ?>
                <input type="hidden" name="id" value="<?= e($editId) ?>">
            <?php endif; ?>

            <label>SKU <input name="sku" value="<?= e($form['sku']) ?>" required maxlength="32"
                              pattern="[A-Za-z0-9][A-Za-z0-9\-]{1,31}" placeholder="LAP-003"></label>
            <label>Name <input name="name" value="<?= e($form['name']) ?>" required maxlength="100"></label>
            <label>Category <input name="category" value="<?= e($form['category']) ?>" required maxlength="50"></label>
            <label>Quantity <input name="quantity" type="number" min="0" max="1000000" step="1"
                                   value="<?= e($form['quantity']) ?>" required></label>
            <label>Unit price (₹) <input name="unit_price" type="number" min="0" step="0.01"
                                         value="<?= e($form['unit_price']) ?>" required></label>

            <div class="actions">
                <button type="submit"><?= $isEditing ? 'Save changes' : 'Add item' ?></button>
                <?php if ($isEditing): ?><a href="index.php">Cancel</a><?php endif; ?>
            </div>
        </form>
    </section>

    <footer class="muted small">
        <a href="health.php">health.php</a> · host <?= e(gethostname() ?: '') ?>
    </footer>
</main>
</body>
</html>
