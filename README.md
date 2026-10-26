# learn-laravel
Learn Laravel framework

## 建立

1. 先執行 `.\start.ps1` 建立執行環境。
2. `composer create-project laravel/laravel example "^12.0"` 建立 Laravel Application。
3. 進入 example 執行 `php -d variables_order=GPCS artisan serve`。

為了配合現有系統的版本，不使用 laravel/installer，
因為 installer 新增專案不能指定 Laravel 的版本。

## Laravel Permission

配合現有系統的版本，所以選擇安裝 Laravel Permission v6，
安裝步驟指令：

1. `composer require spatie/laravel-permission:^6.*`
2. `php artisan vendor:publish --provider="Spatie\Permission\PermissionServiceProvider"`
3. `php artisan optimize:clear`
4. `php artisan migrate`
