# coding: utf-8

require 'spec_helper'
require 'transpec/syntax/operator_matcher'

module Transpec
  class Syntax
    describe OperatorMatcher do
      include ::AST::Sexp
      include_context 'parsed objects'
      include_context 'should object'

      subject(:matcher) do
        OperatorMatcher.new(should_object.matcher_node, source_rewriter, runtime_data)
      end

      let(:runtime_data) { nil }

      let(:record) { matcher.report.records.first }

      describe '.dynamic_analysis_target_node?' do
        let(:nodes) do
          AST::Scanner.scan(ast) do |node, ancestor_nodes|
            return node, ancestor_nodes if node == s(:send, nil, :foo)
          end
          fail 'No target node is found!'
        end

        context 'when the node is argument of #=~' do
          let(:source) do
            <<-END
              it 'matches to foo' do
                subject.should =~ foo
              end
            END
          end

          it 'returns true' do
            OperatorMatcher.dynamic_analysis_target_node?(*nodes).should be_true
          end
        end
      end

      describe '#method_name' do
        context 'when it is operator matcher' do
          let(:source) do
            <<-END
              it 'is 1' do
                subject.should == 1
              end
            END
          end

          # (block
          #   (send nil :it
          #     (str "is 1"))
          #   (args)
          #   (send
          #     (send
          #       (send nil :subject) :should) :==
          #     (int 1)))

          it 'returns the method name' do
            matcher.method_name.should == :==
          end
        end

        context 'when it is non-operator matcher' do
          let(:source) do
            <<-END
              it 'is 1' do
                subject.should eq(1)
              end
            END
          end

          # (block
          #   (send nil :it
          #     (str "is 1"))
          #   (args)
          #   (send
          #     (send nil :subject) :should
          #     (send nil :eq
          #       (int 1))))

          it 'returns the method name' do
            matcher.method_name.should == :eq
          end
        end
      end

      describe '#correct_operator!' do
        before do
          matcher.correct_operator!(parenthesize_arg)
        end

        let(:parenthesize_arg) { true }

        context 'when it is `== 1` form' do
          let(:source) do
            <<-END
              it 'is 1' do
                subject.should == 1
              end
            END
          end

          let(:expected_source) do
            <<-END
              it 'is 1' do
                subject.should eq(1)
              end
            END
          end

          it 'converts into `eq(1)` form' do
            rewritten_source.should == expected_source
          end

          it 'adds record "`== expected` -> `eq(expected)`"' do
            record.original_syntax.should == '== expected'
            record.converted_syntax.should == 'eq(expected)'
          end

          # Operator methods allow their argument to be in the next line,
          # but non-operator methods do not.
          #
          # [1] pry(main)> 1 ==
          # [1] pry(main)* 1
          # => true
          # [2] pry(main)> 1.eql?
          # ArgumentError: wrong number of arguments (0 for 1)
          context 'and its argument is in the next line' do
            let(:source) do
              <<-END
                it 'is 1' do
                  subject.should ==
                    1
                end
              END
            end

            let(:expected_source) do
              <<-END
                it 'is 1' do
                  subject.should eq(
                    1
                  )
                end
              END
            end

            it 'inserts parentheses properly' do
              rewritten_source.should == expected_source
            end

            context 'and false is passed as `parenthesize_arg` argument' do
              let(:parenthesize_arg) { false }

              it 'inserts parentheses properly because they are necessary' do
                rewritten_source.should == expected_source
              end
            end
          end
        end

        context 'when it is `==1` form' do
          let(:source) do
            <<-END
              it 'is 1' do
                subject.should==1
              end
            END
          end

          let(:expected_source) do
            <<-END
              it 'is 1' do
                subject.should eq(1)
              end
            END
          end

          it 'converts into `eq(1)` form' do
            rewritten_source.should == expected_source
          end

          context 'and false is passed as `parenthesize_arg` argument' do
            let(:parenthesize_arg) { false }

            let(:expected_source) do
            <<-END
              it 'is 1' do
                subject.should eq 1
              end
            END
            end

            it 'converts into `eq 1` form' do
              rewritten_source.should == expected_source
            end
          end
        end

        context 'when it is `be == 1` form' do
          let(:source) do
            <<-END
              it 'is 1' do
                subject.should be == 1
              end
            END
          end

          let(:expected_source) do
            <<-END
              it 'is 1' do
                subject.should eq(1)
              end
            END
          end

          it 'converts into `eq(1)` form' do
            rewritten_source.should == expected_source
          end

          it 'adds record "`== expected` -> `eq(expected)`"' do
            record.original_syntax.should == '== expected'
            record.converted_syntax.should == 'eq(expected)'
          end
        end

        context 'when it is `be.==(1)` form' do
          let(:source) do
            <<-END
              it 'is 1' do
                subject.should be.==(1)
              end
            END
          end

          let(:expected_source) do
            <<-END
              it 'is 1' do
                subject.should eq(1)
              end
            END
          end

          it 'converts into `eq(1)` form' do
            rewritten_source.should == expected_source
          end
        end

        context 'when it is `== (2 - 1)` form' do
          let(:source) do
            <<-END
              it 'is 1' do
                subject.should == (2 - 1)
              end
            END
          end

          let(:expected_source) do
            <<-END
              it 'is 1' do
                subject.should eq(2 - 1)
              end
            END
          end

          it 'converts into `eq(2 - 1)` form without superfluous parentheses' do
            rewritten_source.should == expected_source
          end
        end

        context 'when it is `== (5 - 3) / (4 - 2)` form' do
          let(:source) do
            <<-END
              it 'is 1' do
                subject.should == (5 - 3) / (4 - 2)
              end
            END
          end

          let(:expected_source) do
            <<-END
              it 'is 1' do
                subject.should eq((5 - 3) / (4 - 2))
              end
            END
          end

          it 'converts into `eq((5 - 3) / (4 - 2))` form' do
            rewritten_source.should == expected_source
          end
        end

        context "when it is `== { 'key' => 'value' }` form" do
          let(:source) do
            <<-END
              it 'is the hash' do
                subject.should == { 'key' => 'value' }
              end
            END
          end

          let(:expected_source) do
            <<-END
              it 'is the hash' do
                subject.should eq({ 'key' => 'value' })
              end
            END
          end

          it "converts into `eq({ 'key' => 'value' })` form" do
            rewritten_source.should == expected_source
          end

          context 'and false is passed as `parenthesize_arg` argument' do
            let(:parenthesize_arg) { false }

            it 'inserts parentheses to avoid the hash from be interpreted as a block' do
              rewritten_source.should == expected_source
            end
          end
        end

        [
          [:===, 'case-equals to'],
          [:<,   'is less than'],
          [:<=,  'is less than or equals to'],
          [:>,   'is greater than'],
          [:>=,  'is greater than or equals to']
        ].each do |operator, description|
          context "when it is `#{operator} 1` form" do
            let(:source) do
              <<-END
                it '#{description} 1' do
                  subject.should #{operator} 1
                end
              END
            end

            let(:expected_source) do
              <<-END
                it '#{description} 1' do
                  subject.should be #{operator} 1
                end
              END
            end

            it "converts into `be #{operator} 1` form" do
              rewritten_source.should == expected_source
            end

            it "adds record \"`#{operator} expected` -> `be #{operator} expected`\"" do
              record.original_syntax.should == "#{operator} expected"
              record.converted_syntax.should == "be #{operator} expected"
            end
          end

          context "when it is `be #{operator} 1` form" do
            let(:source) do
              <<-END
                it '#{description} 1' do
                  subject.should be #{operator} 1
                end
              END
            end

            it 'does nothing' do
              rewritten_source.should == source
            end

            it 'reports nothing' do
              matcher.report.records.should be_empty
            end
          end
        end

        context 'when it is `=~ /pattern/` form' do
          let(:source) do
            <<-END
              it 'matches the pattern' do
                subject.should =~ /pattern/
              end
            END
          end

          let(:expected_source) do
            <<-END
              it 'matches the pattern' do
                subject.should match(/pattern/)
              end
            END
          end

          it 'converts into `match(/pattern/)` form' do
            rewritten_source.should == expected_source
          end

          it 'adds record "`=~ /pattern/` -> `match(/pattern/)`"' do
            record.original_syntax.should == '=~ /pattern/'
            record.converted_syntax.should == 'match(/pattern/)'
          end
        end

        context 'when it is `=~/pattern/` form' do
          let(:source) do
            <<-END
              it 'matches the pattern' do
                subject.should=~/pattern/
              end
            END
          end

          let(:expected_source) do
            <<-END
              it 'matches the pattern' do
                subject.should match(/pattern/)
              end
            END
          end

          it 'converts into `match(/pattern/)` form' do
            rewritten_source.should == expected_source
          end
        end

        context 'when it is `be =~ /pattern/` form' do
          let(:source) do
            <<-END
              it 'matches the pattern' do
                subject.should be =~ /pattern/
              end
            END
          end

          let(:expected_source) do
            <<-END
              it 'matches the pattern' do
                subject.should match(/pattern/)
              end
            END
          end

          it 'converts into `match(/pattern/)` form' do
            rewritten_source.should == expected_source
          end
        end

        context 'when it is `=~ [1, 2]` form' do
          let(:source) do
            <<-END
              it 'contains 1 and 2' do
                subject.should =~ [1, 2]
              end
            END
          end

          let(:expected_source) do
            <<-END
              it 'contains 1 and 2' do
                subject.should match_array([1, 2])
              end
            END
          end

          it 'converts into `match_array([1, 2])` form' do
            rewritten_source.should == expected_source
          end

          it 'adds record "`=~ [1, 2]` -> `match_array([1, 2])`"' do
            record.original_syntax.should == '=~ [1, 2]'
            record.converted_syntax.should == 'match_array([1, 2])'
          end
        end

        context 'when it is `=~[1, 2]` form' do
          let(:source) do
            <<-END
              it 'contains 1 and 2' do
                subject.should=~[1, 2]
              end
            END
          end

          let(:expected_source) do
            <<-END
              it 'contains 1 and 2' do
                subject.should match_array([1, 2])
              end
            END
          end

          it 'converts into `match_array([1, 2])` form' do
            rewritten_source.should == expected_source
          end
        end

        context 'when it is `be =~ [1, 2]` form' do
          let(:source) do
            <<-END
              it 'contains 1 and 2' do
                subject.should be =~ [1, 2]
              end
            END
          end

          let(:expected_source) do
            <<-END
              it 'contains 1 and 2' do
                subject.should match_array([1, 2])
              end
            END
          end

          it 'converts into `match_array([1, 2])` form' do
            rewritten_source.should == expected_source
          end
        end

        context 'when it is `=~ variable` form' do
          context 'and runtime type of the variable is array' do
            include_context 'dynamic analysis objects'

            let(:source) do
              <<-END
                describe 'example' do
                  it 'contains 1 and 2' do
                    variable = [1, 2]
                    [2, 1].should =~ variable
                  end
                end
              END
            end

            let(:expected_source) do
              <<-END
                describe 'example' do
                  it 'contains 1 and 2' do
                    variable = [1, 2]
                    [2, 1].should match_array(variable)
                  end
                end
              END
            end

            it 'converts into `match_array(variable)` form' do
              rewritten_source.should == expected_source
            end
          end

          context 'and no runtime type information is provided' do
            let(:source) do
              <<-END
                it 'matches the pattern' do
                  subject.should =~ variable
                end
              END
            end

            let(:expected_source) do
              <<-END
                it 'matches the pattern' do
                  subject.should match(variable)
                end
              END
            end

            it 'converts into `match(variable)` form' do
              rewritten_source.should == expected_source
            end
          end
        end
      end

      describe '#parenthesize!' do
        before do
          matcher.parenthesize!(always)
        end

        let(:always) { true }

        context 'when its argument is already in parentheses' do
          let(:source) do
            <<-END
              it 'is 1' do
                subject.should eq(1)
              end
            END
          end

          it 'does nothing' do
            rewritten_source.should == source
          end
        end

        context 'when its argument is not in parentheses' do
          let(:source) do
            <<-END
              it 'is 1' do
                subject.should eq 1
              end
            END
          end

          context 'and true is passed as `always` argument' do
            let(:always) { true }

            let(:expected_source) do
            <<-END
              it 'is 1' do
                subject.should eq(1)
              end
            END
            end

            it 'inserts parentheses' do
              rewritten_source.should == expected_source
            end
          end

          context 'and false is passed as `always` argument' do
            let(:always) { false }

            let(:expected_source) do
            <<-END
              it 'is 1' do
                subject.should eq 1
              end
            END
            end

            it 'does not nothing' do
              rewritten_source.should == expected_source
            end
          end
        end

        context 'when its multiple arguments are not in parentheses' do
          let(:source) do
            <<-END
              it 'contains 1 and 2' do
                subject.should include 1, 2
              end
            END
          end

          let(:expected_source) do
            <<-END
              it 'contains 1 and 2' do
                subject.should include(1, 2)
              end
            END
          end

          it 'inserts parentheses' do
            rewritten_source.should == expected_source
          end
        end

        context 'when its argument is a string literal' do
          let(:source) do
            <<-END
              it "is 'string'" do
                subject.should eq 'string'
              end
            END
          end

          let(:expected_source) do
            <<-END
              it "is 'string'" do
                subject.should eq('string')
              end
            END
          end

          it 'inserts parentheses' do
            rewritten_source.should == expected_source
          end
        end

        context 'when its argument is a here document' do
          let(:source) do
            <<-END
              it 'returns the document' do
                subject.should eq <<-HEREDOC
                foo
                HEREDOC
              end
            END
          end

          # (block
          #   (send nil :it
          #     (str "returns the document"))
          #   (args)
          #   (send
          #     (send nil :subject) :should
          #     (send nil :eq
          #       (str "                foo\n"))))

          it 'does nothing' do
            rewritten_source.should == source
          end
        end

        context 'when its argument is a here document with chained method' do
          let(:source) do
            <<-END
              it 'returns the document' do
                subject.should eq <<-HEREDOC.gsub('foo', 'bar')
                foo
                HEREDOC
              end
            END
          end

          # (block
          #   (send nil :it
          #     (str "returns the document"))
          #   (args)
          #   (send
          #     (send nil :subject) :should
          #     (send nil :eq
          #       (send
          #         (str "                foo\n") :gsub
          #         (str "foo")
          #         (str "bar")))))

          it 'does nothing' do
            rewritten_source.should == source
          end
        end

        context 'when its argument is a here document with interpolation' do
          let(:source) do
            <<-'END'
              it 'returns the document' do
                string = 'foo'
                subject.should eq <<-HEREDOC
                #{string}
                HEREDOC
              end
            END
          end

          # (block
          #   (send nil :it
          #     (str "returns the document"))
          #   (args)
          #   (begin
          #     (lvasgn :string
          #       (str "foo"))
          #     (send
          #       (send nil :subject) :should
          #       (send nil :eq
          #         (dstr
          #           (str "                ")
          #           (begin
          #             (lvar :string))
          #           (str "\n"))))))

          it 'does nothing' do
            rewritten_source.should == source
          end
        end
      end
    end
  end
end