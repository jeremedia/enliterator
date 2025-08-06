module Navigator
  module Operations
    class DefaultOperation < BaseOperation
      def initialize(user_text)
        super(nil)
        @user_text = user_text
      end
      
      def execute
        {
          success: true,
          understood: false,
          user_input: @user_text,
          message: "I'm still learning to understand that type of request"
        }
      end
    end
  end
end