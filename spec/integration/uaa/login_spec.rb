require 'spec_helper'

describe 'Logging into a director with UAA authentication', type: :integration do
  with_reset_sandbox_before_each(user_authentication: 'uaa')

  before do
    bosh_runner.run("target #{current_sandbox.director_url}")
    bosh_runner.run('logout')
  end

  it 'logs in successfully' do
    bosh_runner.run_interactively('login') do |runner|
      expect(runner).to have_output 'Email:'
      runner.send_keys 'marissa'
      expect(runner).to have_output 'Password:'
      runner.send_keys 'koala'
      expect(runner).to have_output 'One Time Code'
      runner.send_keys 'dontcare' # UAA only uses this for SAML, but always prompts for it
      expect(runner).to have_output "Logged in as `marissa'"
    end

    output = bosh_runner.run('deployments',
      { failure_expected: true } # If you have no deployments, exit status is non-zero
    )
    expect(output).to match /No deployments/
  end

  it 'fails to log in when incorrect credentials were provided' do
    bosh_runner.run_interactively('login') do |runner|
      expect(runner).to have_output 'Email:'
      runner.send_keys 'fake'
      expect(runner).to have_output 'Password:'
      runner.send_keys 'fake'
      expect(runner).to have_output 'One Time Code'
      runner.send_keys 'dontcare'
      expect(runner).to have_output 'Failed to log in'
    end

    output = bosh_runner.run('deployments',
      { failure_expected: true }
    )
    expect(output).to match /Please log in first/
  end
end
