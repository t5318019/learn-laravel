<?php

namespace App\Http\Controllers;

use App\Models\User;
use Illuminate\Http\Request;

class PermissionController extends Controller
{
    private const USER_NAMES = [
        'Example User',
        'Example Admin User',
        'Example Super-Admin User',
    ];

    private const PERMISSIONS = [
        'edit articles',
        'delete articles',
        'publish articles',
        'unpublish articles',
    ];

    /**
     * Handle the incoming request.
     */
    public function __invoke(Request $request)
    {
        return collect(self::USER_NAMES)
            ->map(fn (string $name) => $this->describe(User::where('name', $name)->first()))
            ->join('<hr>');
    }

    private function describe(User $user): string
    {
        $lines = [$user->name];

        // get a list of all permissions directly assigned to the user
        $lines[] = 'user->getPermissionNames() = '.$user->getPermissionNames()->join(', '); // collection of name strings
        $lines[] = 'user->permissions = '.$user->permissions->pluck('name')->join(', '); // collection of permission objects

        // get all permissions for the user, either directly, or from roles, or from both
        $lines[] = 'user->getDirectPermissions() = '.$user->getDirectPermissions()->pluck('name')->join(', ');
        $lines[] = 'user->getPermissionsViaRoles() = '.$user->getPermissionsViaRoles()->pluck('name')->join(', ');
        $lines[] = 'user->getAllPermissions() = '.$user->getAllPermissions()->pluck('name')->join(', ');

        // get the names of the user's roles
        $lines[] = 'Role = '.$user->getRoleNames()->join(', ');

        foreach (self::PERMISSIONS as $permission) {
            $lines[] = "user->hasPermissionTo({$permission}) = ".($user->hasPermissionTo($permission) ? 'true' : 'false');
        }

        return implode('<br>', $lines).'<br>';
    }
}
