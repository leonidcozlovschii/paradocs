require 'spec_helper'
require "parametric/dsl"

describe "classes including DSL module" do
  let!(:parent) do
    Class.new do
      include Parametric::DSL

      schema do
        field(:title).type(:string)
        field(:age).type(:integer)
      end
    end
  end

  let!(:child) do
    Class.new(parent) do
      schema do
        field(:age).type(:string)
        field(:description).type(:string)
      end
    end
  end

  describe "#schema" do
    let(:input) {
      {
        title: "A title",
        age: 38,
        description: "A description"
      }
    }

    it "merges parent's schema into child's" do
      parent_output = parent.schema.resolve(input).output
      child_output = child.schema.resolve(input).output

      expect(parent_output.keys).to match_array([:title, :age])
      expect(parent_output[:title]).to eq "A title"
      expect(parent_output[:age]).to eq 38

      expect(child_output.keys).to match_array([:title, :age, :description])
      expect(child_output[:title]).to eq "A title"
      expect(child_output[:age]).to eq "38"
      expect(child_output[:description]).to eq "A description"
    end
  end
end
