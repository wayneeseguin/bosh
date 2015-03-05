require 'spec_helper'

describe 'cli: login', type: :integration do
  context 'when targeting a director using UAA for user authentication' do
    with_reset_sandbox_before_each(user_authentication: 'uaa')

    it 'shows the right password prompts from UAA' do
      pending "figuring out how to test UAA integration"
      bosh_runner.run("target #{current_sandbox.director_url}")

      output = bosh_runner.run_interactively("login") do |terminal|
        terminal.wait_for_output("Email:")
        terminal.send_input("admin")
        terminal.wait_for_output("Password:")
        terminal.send_input("admin")
        terminal.wait_for_output("One Time Code")
        terminal.send_input("myfancycode")
      end

      # expect(output).to include("Logged in")
    end

    it 'blows up if run non-interactively' do
      pending "figuring out how to test UAA integration"
      bosh_runner.run("target #{current_sandbox.director_url}")
      expect(bosh_runner.run('login'), failure_expected: true).to include("not supported")
    end
  end

  context 'when targeting a director using basic user authentication' do
    with_reset_sandbox_before_each

    context 'interactively' do
      it 'can log in' do
        bosh_runner.run("target #{current_sandbox.director_url}")
        output = bosh_runner.run_interactively('login') do |terminal|
          terminal.wait_for_output("username:")
          terminal.send_input("admin")
          terminal.wait_for_output("password:")
          terminal.send_input("admin")
        end

        expect(output).to include("Logged in")
      end
    end

    it 'requires login when talking to director' do
      expect(bosh_runner.run('properties', failure_expected: true)).to match(/please choose target first/i)
      bosh_runner.run("target #{current_sandbox.director_url}")
      expect(bosh_runner.run('properties', failure_expected: true)).to match(/please log in first/i)
    end

    it 'can log in as a user, create another user and delete created user' do
      bosh_runner.run("target #{current_sandbox.director_url}")
      bosh_runner.run('login admin admin')
      expect(bosh_runner.run('create user john john-pass')).to match(/User `john' has been created/i)

      expect(bosh_runner.run('login john john-pass')).to match(/Logged in as `john'/i)
      expect(bosh_runner.run('create user jane jane-pass')).to match(/user `jane' has been created/i)
      bosh_runner.run('logout')

      expect(bosh_runner.run('login jane jane-pass')).to match(/Logged in as `jane'/i)
      expect(bosh_runner.run('delete user john')).to match(/User `john' has been deleted/i)
      bosh_runner.run('logout')

      expect(bosh_runner.run('login john john-pass', failure_expected: true)).to match(/Cannot log in as `john'/i)
      expect(bosh_runner.run('login jane jane-pass')).to match(/Logged in as `jane'/i)
    end

    it 'cannot log in if password is invalid' do
      bosh_runner.run("target #{current_sandbox.director_url}")
      bosh_runner.run('login admin admin')
      bosh_runner.run('create user jane pass')
      bosh_runner.run('logout')
      expect_output('login jane foo', <<-OUT)
        Cannot log in as `jane'
      OUT
    end
  end
end
