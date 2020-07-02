# frozen_string_literal: true

# Copyright 2020 OpenTelemetry Authors
#
# SPDX-License-Identifier: Apache-2.0

require 'test_helper'

describe OpenTelemetry::Instrumentation::Registry do
  after do
    OpenTelemetry.instance_variable_set(:@instrumentation_registry, nil)
  end

  let(:registry) do
    OpenTelemetry::Instrumentation::Registry.new
  end

  let(:instrumentation) do
    Class.new(OpenTelemetry::Instrumentation::BaseInstrumentation) do
      instrumentation_name 'TestInstrumentation'
      instrumentation_version '0.1.1'
    end
  end

  describe '#register, #lookup' do
    it 'registers and looks up instrumentations' do
      registry.register(instrumentation)
      _(registry.lookup(instrumentation.instance.name)).must_equal(instrumentation.instance)
    end
  end

  describe 'installation' do
    before do
      TestInstrumentation1 = Class.new(OpenTelemetry::Instrumentation::BaseInstrumentation) do
        install { 1 + 1 }
        present { true }
      end
      TestInstrumentation2 = Class.new(OpenTelemetry::Instrumentation::BaseInstrumentation) do
        install { 2 + 2 }
        present { true }
      end
      @instrumentation = [TestInstrumentation1, TestInstrumentation2]
      @instrumentation.each { |instrumentation| registry.register(instrumentation) }
    end

    after do
      @instrumentation.each { |instrumentation| Object.send(:remove_const, instrumentation.name.to_sym) }
    end

    describe '#install_all' do
      it 'installs all registered instrumentations by default' do
        _(@instrumentation.map(&:instance).none? { |a| a.installed? }) # rubocop:disable Style/SymbolProc
          .must_equal(true)
        registry.install_all
        _(@instrumentation.map(&:instance).all? { |a| a.installed? }).must_equal(true) # rubocop:disable Style/SymbolProc
      end

      it 'passes config to instrumentations when installing' do
        _(TestInstrumentation1.instance.config).must_equal({})
        _(TestInstrumentation2.instance.config).must_equal({})

        registry.install_all('TestInstrumentation1' => { a: 'a' },
                             'TestInstrumentation2' => { b: 'b' })

        _(TestInstrumentation1.instance.config).must_equal(a: 'a')
        _(TestInstrumentation2.instance.config).must_equal(b: 'b')
      end
    end

    describe '#install' do
      it 'installs specified instrumentations' do
        _(@instrumentation.map(&:instance).none? { |a| a.installed? }) # rubocop:disable Style/SymbolProc
          .must_equal(true)
        registry.install(%w[TestInstrumentation1])
        _(TestInstrumentation1.instance.installed?).must_equal(true)
        _(TestInstrumentation2.instance.installed?).must_equal(false)
      end

      it 'passes config to instrumentations when installing' do
        _(TestInstrumentation1.instance.config).must_equal({})
        _(TestInstrumentation2.instance.config).must_equal({})

        registry.install(%w[TestInstrumentation1 TestInstrumentation2],
                         'TestInstrumentation1' => { a: 'a' },
                         'TestInstrumentation2' => { b: 'b' })

        _(TestInstrumentation1.instance.config).must_equal(a: 'a')
        _(TestInstrumentation2.instance.config).must_equal(b: 'b')
      end
    end
  end

  describe 'buggy instrumentations' do
    before do
      BuggyInstrumentation = Class.new(OpenTelemetry::Instrumentation::BaseInstrumentation) do
        install { raise 'oops' }
      end
      registry.register(BuggyInstrumentation)
    end

    after do
      Object.send(:remove_const, :BuggyInstrumentation)
    end

    describe 'install' do
      it 'handles exceptions during installation' do
        instance = BuggyInstrumentation.instance
        _(instance.installed?).must_equal(false)
        registry.install(%w[BuggyInstrumentation])
        _(instance.installed?).must_equal(false)
      end
    end

    describe 'install_all' do
      it 'handles exceptions during installation' do
        instance = BuggyInstrumentation.instance
        _(instance.installed?).must_equal(false)
        registry.install_all
        _(instance.installed?).must_equal(false)
      end
    end
  end
end
