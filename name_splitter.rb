require 'rubygems'
require 'rspec'


describe NameSplitter do
  it "should correctly return parts of a name" do
    parts = NameSplitter.split_word("sebastian")
    parts.inlcude?("seb").should == true
    parts.inlcude?("sebast").should == true
    parts.inlcude?("sebastian").should == true

    parts = NameSplitter.split_word("eide")
    parts.inlcude?("eid").should == true
    parts.inlcude?("eide").should == true
  end

  it "should correctly split up a full name" do
    name = "Sebastian Probst Eide"
    parts = NameSplitter.split_name(name)
    parts.inlcude?("seb").should == true
    parts.inlcude?("sebast").should == true
    parts.inlcude?("sebastian").should == true
    parts.inlcude?("pro").should == true
    parts.inlcude?("probst").should == true
    parts.inlcude?("eid").should == true
    parts.inlcude?("eide").should == true
  end
end
