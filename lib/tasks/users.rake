namespace :users do
  desc 'Create or update an admin user. Usage: bin/rails users:create_admin EMAIL=j@zinod.com PASSWORD=cheese28 NAME="Admin"'
  task create_admin: :environment do
    email = ENV['EMAIL'] || 'j@zinod.com'
    password = ENV['PASSWORD'] || 'cheese28'
    name = ENV['NAME'] || 'Administrator'

    raise 'EMAIL is required' if email.blank?
    raise 'PASSWORD is required' if password.blank?

    user = User.find_or_initialize_by(email: email)
    user.name = name if user.name.blank?
    user.admin = true

    # Always set password to ensure access after DB reset
    user.password = password
    user.password_confirmation = password

    if user.save
      puts "✅ Admin user ensured: #{user.email} (admin=#{user.admin})"
    else
      puts "❌ Failed to create/update admin user: #{user.errors.full_messages.join(', ')}"
      exit 1
    end
  end
end

