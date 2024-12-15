<?php
namespace Deployer;

require 'recipe/laravel.php';

// Config
set('repository', 'https://github.com/issacgram/depapp.git');
set('git_tty', false);
set('ssh_multiplexing', false);
set('debug', true);

// Version management
set('app_version', function () {
    try {
        $envContent = file_get_contents('.env');
        if (preg_match('/APP_VERSION=([0-9]+\.[0-9]+\.[0-9]+)/', $envContent, $matches)) {
            $currentVersion = $matches[1];
        } else {
            $currentVersion = '1.0.0';
        }
        
        $versionParts = explode('.', $currentVersion);
        $versionParts[2] = (int)$versionParts[2] + 1;
        return implode('.', $versionParts);
    } catch (\Exception $e) {
        return '1.0.0';
    }
});

// Create GitHub release task
task('create-github-release', function() {
    $version = get('app_version');
    runLocally('gh release create v' . $version . ' --title "Release v' . $version . '" --notes "Release version ' . $version . '"');
});

// Fix permissions task
task('fix:permissions', function () {
    run('chmod -R 775 {{release_path}}/storage');
    run('chmod -R 775 {{release_path}}/bootstrap/cache');
    run('chown -R deployuser:www-data {{release_path}}');
});

// Deploy version task
desc('Deploy with version tag');
task('deploy-version', function () {
    try {
        // Unlock any existing deployment
        invoke('deploy:unlock');

        $newVersion = get('app_version');
        
        // Update .env file
        if (file_exists('.env')) {
            $envContent = file_get_contents('.env');
            $envContent = preg_replace(
                '/APP_VERSION=.*/',
                'APP_VERSION=' . $newVersion,
                $envContent
            );
            file_put_contents('.env', $envContent);
        }

        // Git operations
        runLocally('git add .');
        $commitMessage = ask('Enter commit message', 'Release version ' . $newVersion);
        runLocally('git commit -m "' . $commitMessage . '"');
        runLocally('git tag -a v' . $newVersion . ' -m "Version ' . $newVersion . '"');
        runLocally('git push origin main --tags');

        // Create GitHub release
        invoke('create-github-release');

        // Deploy
        invoke('deploy');

        writeln("<info>Successfully deployed version " . $newVersion . "</info>");
    } catch (\Exception $e) {
        invoke('deploy:unlock');
        throw $e;
    }
});

// Hosts
host('89.116.48.146')
    ->set('remote_user', 'deployuser')
    ->set('deploy_path', '/var/www/phpgram.info')
    ->set('ssh_arguments', [
        '-o UserKnownHostsFile=/dev/null',
        '-o StrictHostKeyChecking=no'
    ])
    ->set('keep_releases', 5);

// Task ordering
before('deploy:symlink', 'fix:permissions');
after('deploy:failed', 'deploy:unlock');
after('deploy:success', 'artisan:cache:clear');
after('deploy:success', 'artisan:config:cache');
after('deploy:success', 'artisan:route:cache');
after('deploy:success', 'artisan:view:cache');