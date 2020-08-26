# frozen_string_literal: true

RSpec.describe RuboCop::AST::NodePattern::Lexer do
  let(:source) { '(send nil? #func(:foo) #func (bar))' }
  let(:lexer) { described_class.new(source) }
  let(:tokens) do
    tokens = []
    while (token = lexer.next_token)
      tokens << token
    end
    tokens
  end

  it 'provides tokens via next_token' do
    type, (text, range) = tokens[3]
    expect(type).to eq :tFUNCTION_CALL
    expect(text).to eq :func
    expect(range.to_range).to eq 11...16

    expect(tokens.map(&:first)).to eq [
      '(',
      :tNODE_TYPE,
      :tPREDICATE,
      :tFUNCTION_CALL, :tARG_LIST, :tSYMBOL, ')',
      :tFUNCTION_CALL,
      '(', :tNODE_TYPE, ')',
      ')'
    ]
  end

  context 'given $type+' do
    let(:source) { '(array sym $int+ x)' }

    it 'works' do
      expect(tokens.map(&:last).map(&:first)).to eq \
        %i[( array sym $ int + x )]
    end
  end
end
